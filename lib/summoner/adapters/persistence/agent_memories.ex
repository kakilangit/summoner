defmodule Summoner.Adapters.Persistence.AgentMemories do
  @moduledoc """
  Persistence adapter for agent memories.

  Implements CRUD, vector similarity search, access tracking,
  confidence decay, and pruning for the agent memory system.
  """

  import Ecto.Query, warn: false

  alias Summoner.Domain.Schemas.AgentMemory
  alias Summoner.Ports.Persistence.Pagination
  alias Summoner.Repo

  @behaviour Summoner.Ports.Persistence.AgentMemories.Adapter

  @doc "Creates a new agent memory."
  @impl true
  def create_memory(attrs) do
    %AgentMemory{}
    |> AgentMemory.changeset(attrs)
    |> Ecto.Changeset.put_change(:last_accessed_at, DateTime.utc_now())
    |> Repo.insert()
  end

  @doc "Gets an agent memory by ID."
  @impl true
  def get_memory!(id) do
    Repo.get!(AgentMemory, id)
  end

  @doc "Lists memories for an agent with optional type filter and limit."
  @impl true
  def list_by_agent(agent_id, opts \\ []) do
    type = Keyword.get(opts, :type)
    limit = Keyword.get(opts, :limit)

    AgentMemory
    |> where([m], m.agent_id == ^agent_id)
    |> maybe_filter_type(type)
    |> maybe_limit(limit)
    |> order_by([m], desc: m.inserted_at)
    |> Repo.all()
  end

  @doc "Updates an agent memory."
  @impl true
  def update_memory(%AgentMemory{} = memory, attrs) do
    memory
    |> AgentMemory.changeset(attrs)
    |> Repo.update()
  end

  @doc "Updates only the embedding vector for a memory."
  @impl true
  def update_embedding(%AgentMemory{} = memory, embedding) do
    memory
    |> AgentMemory.embedding_changeset(%{embedding: embedding})
    |> Repo.update()
  end

  @doc "Deletes an agent memory."
  @impl true
  def delete_memory(%AgentMemory{} = memory) do
    Repo.delete(memory)
  end

  @doc "Searches memories by cosine similarity using pgvector."
  @impl true
  def cosine_search(agent_id, embedding, opts \\ []) do
    min_confidence = Keyword.get(opts, :min_confidence, 0.1)
    limit = Keyword.get(opts, :limit, 5)

    AgentMemory
    |> where([m], m.agent_id == ^agent_id and m.confidence >= ^min_confidence)
    |> where([m], not is_nil(m.embedding))
    |> order_by([m], fragment("embedding <=> ?", ^embedding))
    |> limit(^limit)
    |> select_merge([m], %{similarity: fragment("1 - (embedding <=> ?)", ^embedding)})
    |> Repo.all()
  end

  @doc "Increments access count and updates last accessed timestamp."
  @impl true
  def update_access(%AgentMemory{} = memory) do
    now = DateTime.utc_now()

    AgentMemory
    |> where([m], m.id == ^memory.id)
    |> Repo.update_all(set: [last_accessed_at: now], inc: [access_count: 1])

    {:ok, Repo.get!(AgentMemory, memory.id)}
  end

  @doc """
  Decays confidence for memories not accessed since cutoff.

  Computes the number of decay intervals per row based on days since
  last access, then applies `confidence * factor^intervals`.
  """
  @impl true
  def decay_batch(%DateTime{} = cutoff, decay_factor, interval_days) do
    from(m in AgentMemory,
      where: m.last_accessed_at < ^cutoff,
      update: [
        set: [
          confidence:
            fragment(
              "confidence * power(?, floor(extract(epoch from now() - last_accessed_at) / 86400 / ?)::int)",
              ^decay_factor,
              ^interval_days
            )
        ]
      ]
    )
    |> Repo.update_all([])
  end

  @doc "Prunes memories below a confidence threshold for an agent."
  @impl true
  def prune_below(agent_id, threshold) do
    AgentMemory
    |> where([m], m.agent_id == ^agent_id and m.confidence < ^threshold)
    |> Repo.delete_all()
  end

  @doc "Counts memories for an agent."
  @impl true
  def count_by_agent(agent_id) do
    AgentMemory
    |> where([m], m.agent_id == ^agent_id)
    |> Repo.aggregate(:count)
  end

  @doc "Returns distinct agent IDs that have at least one memory."
  @impl true
  def list_agent_ids_with_memories do
    AgentMemory
    |> select([m], m.agent_id)
    |> distinct(true)
    |> Repo.all()
  end

  @doc """
  Prunes excess memories for an agent, keeping only the top `max_count`
  by confidence (highest kept). Deletes the rest.
  """
  @impl true
  def prune_excess(agent_id, max_count) do
    keep_ids =
      AgentMemory
      |> where([m], m.agent_id == ^agent_id)
      |> order_by([m], desc: m.confidence, desc: m.last_accessed_at)
      |> limit(^max_count)
      |> select([m], m.id)
      |> Repo.all()

    AgentMemory
    |> where([m], m.agent_id == ^agent_id and m.id not in ^keep_ids)
    |> Repo.delete_all()
  end

  defp maybe_filter_type(query, nil), do: query
  defp maybe_filter_type(query, type), do: where(query, [m], m.type == ^type)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  @doc "Lists memories for an agent with pagination, sorting, and filtering."
  @impl true
  def list_memories_paginated(agent_id, opts \\ []) do
    AgentMemory
    |> where([m], m.agent_id == ^agent_id)
    |> maybe_filter_type(Keyword.get(opts, :type))
    |> Pagination.paginate(opts)
  end
end
