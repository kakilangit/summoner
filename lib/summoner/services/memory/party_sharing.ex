defmodule Summoner.Services.Memory.PartySharing do
  @moduledoc """
  Replicates shareable memories (fact, procedure) to peer agents
  in the same party (swarm) at reduced confidence.

  Called after a memory is created via `__remember__`. Duplicate
  detection uses `MemoryDeduplication` to avoid redundant copies.
  """

  require Logger

  alias Summoner.Domain.Policies.MemoryDeduplication
  alias Summoner.Ports.Persistence.AgentMemories
  alias Summoner.Ports.Persistence.Swarms

  @shareable_types [:fact, :procedure]
  @sharing_factor 0.7

  @doc """
  Shares a memory with all peer agents in the same party.

  Only `:fact` and `:procedure` types are shared. The replicated
  memory gets `confidence * 0.7`. Duplicates are skipped.
  """
  @spec share_memory(struct()) :: :ok
  def share_memory(%{type: type} = memory) when type in @shareable_types do
    memory.agent_id
    |> Swarms.list_peer_agent_ids()
    |> Enum.reject(&duplicate_exists?(&1, memory))
    |> Enum.each(&share_to_peer(&1, memory))
  end

  def share_memory(_memory), do: :ok

  defp share_to_peer(peer_id, memory) do
    attrs = %{
      content: memory.content,
      type: memory.type,
      agent_id: peer_id,
      workspace_id: memory.workspace_id,
      confidence: memory.confidence * @sharing_factor,
      source_conversation_id: memory.source_conversation_id,
      embedding: memory.embedding
    }

    case AgentMemories.create_memory(attrs) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to share memory to agent #{peer_id}: #{inspect(reason)}")
    end
  end

  defp duplicate_exists?(agent_id, memory) do
    case memory.embedding do
      nil ->
        # No embedding — fall back to text comparison on a small sample
        existing = AgentMemories.list_by_agent(agent_id, limit: 20)
        Enum.any?(existing, fn m -> MemoryDeduplication.duplicate?(m.content, memory.content) end)

      embedding ->
        # Use cosine similarity — a near-identical memory will have similarity > 0.95
        matches = AgentMemories.cosine_search(agent_id, embedding, limit: 1, min_confidence: 0.0)
        match?([%{similarity: s} | _] when s > 0.95, matches)
    end
  end
end
