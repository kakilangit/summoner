defmodule Summoner.Ports.Persistence.AgentMemories do
  @moduledoc "Port for agent memory persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :agent_memories],
             Summoner.Adapters.Persistence.AgentMemories
           )

  defdelegate create_memory(attrs), to: @adapter
  defdelegate get_memory!(id), to: @adapter
  defdelegate list_by_agent(agent_id, opts \\ []), to: @adapter
  defdelegate update_memory(memory, attrs), to: @adapter
  defdelegate update_embedding(memory, embedding), to: @adapter
  defdelegate delete_memory(memory), to: @adapter
  defdelegate cosine_search(agent_id, embedding, opts \\ []), to: @adapter
  defdelegate update_access(memory), to: @adapter
  defdelegate decay_batch(cutoff, decay_factor, interval_days), to: @adapter
  defdelegate prune_below(agent_id, threshold), to: @adapter
  defdelegate count_by_agent(agent_id), to: @adapter
  defdelegate list_agent_ids_with_memories(), to: @adapter
  defdelegate prune_excess(agent_id, max_count), to: @adapter
  defdelegate list_memories_paginated(agent_id, opts \\ []), to: @adapter
end
