defmodule Summoner.Adapters.Persistence.KnowledgeBases do
  @moduledoc """
  Persistence adapter for knowledge bases.

  Implements CRUD, agent linking, and paginated listing
  for the RAG knowledge base system.
  """

  import Ecto.Query, warn: false

  alias Summoner.Domain.Schemas.KnowledgeBase
  alias Summoner.Domain.Schemas.KnowledgeBaseAgent
  alias Summoner.Ports.Persistence.Pagination
  alias Summoner.Repo

  @behaviour Summoner.Ports.Persistence.KnowledgeBases.Adapter

  @doc "Creates a new knowledge base in a workspace."
  @impl true
  def create_knowledge_base(workspace_id, attrs) do
    %KnowledgeBase{workspace_id: workspace_id}
    |> KnowledgeBase.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Gets a knowledge base by ID within a workspace. Raises if not found."
  @impl true
  def get_knowledge_base!(workspace_id, id) do
    KnowledgeBase
    |> where([kb], kb.workspace_id == ^workspace_id and kb.id == ^id)
    |> Repo.one!()
  end

  @doc "Gets a knowledge base by ID within a workspace. Returns nil if not found."
  @impl true
  def get_knowledge_base(workspace_id, id) do
    KnowledgeBase
    |> where([kb], kb.workspace_id == ^workspace_id and kb.id == ^id)
    |> Repo.one()
  end

  @doc "Lists all knowledge bases in a workspace."
  @impl true
  def list_knowledge_bases(workspace_id) do
    KnowledgeBase
    |> where([kb], kb.workspace_id == ^workspace_id)
    |> order_by([kb], desc: kb.inserted_at)
    |> Repo.all()
  end

  @doc "Lists knowledge bases in a workspace with pagination."
  @impl true
  def list_knowledge_bases_paginated(workspace_id, opts \\ []) do
    KnowledgeBase
    |> where([kb], kb.workspace_id == ^workspace_id)
    |> Pagination.paginate(opts)
  end

  @doc "Updates a knowledge base."
  @impl true
  def update_knowledge_base(%KnowledgeBase{} = kb, attrs) do
    kb
    |> KnowledgeBase.changeset(attrs)
    |> Repo.update()
  end

  @doc "Updates status fields for a knowledge base."
  @impl true
  def update_status(%KnowledgeBase{} = kb, attrs) do
    kb
    |> KnowledgeBase.status_changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a knowledge base."
  @impl true
  def delete_knowledge_base(%KnowledgeBase{} = kb) do
    Repo.delete(kb)
  end

  @doc "Links an agent to a knowledge base."
  @impl true
  def link_agent(knowledge_base_id, agent_id) do
    %KnowledgeBaseAgent{}
    |> KnowledgeBaseAgent.changeset(%{knowledge_base_id: knowledge_base_id, agent_id: agent_id})
    |> Repo.insert()
  end

  @doc "Unlinks an agent from a knowledge base."
  @impl true
  def unlink_agent(knowledge_base_id, agent_id) do
    KnowledgeBaseAgent
    |> where([kba], kba.knowledge_base_id == ^knowledge_base_id and kba.agent_id == ^agent_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      kba -> Repo.delete(kba)
    end
  end

  @doc "Lists agents linked to a knowledge base."
  @impl true
  def list_linked_agents(knowledge_base_id) do
    KnowledgeBaseAgent
    |> where([kba], kba.knowledge_base_id == ^knowledge_base_id)
    |> preload(:agent)
    |> Repo.all()
    |> Enum.map(& &1.agent)
  end

  @doc "Lists knowledge bases linked to an agent."
  @impl true
  def list_knowledge_bases_for_agent(agent_id) do
    KnowledgeBase
    |> join(:inner, [kb], kba in KnowledgeBaseAgent,
      on: kba.knowledge_base_id == kb.id and kba.agent_id == ^agent_id
    )
    |> order_by([kb], desc: kb.inserted_at)
    |> Repo.all()
  end
end
