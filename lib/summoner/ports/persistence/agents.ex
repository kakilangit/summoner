defmodule Summoner.Ports.Persistence.Agents do
  @moduledoc "Port for agent persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :agents],
             Summoner.Adapters.Persistence.Agents
           )

  # CRUD
  defdelegate create_agent(scope, attrs), to: @adapter
  defdelegate create_remote_agent(scope, attrs), to: @adapter
  defdelegate update_remote_agent(scope, agent, attrs), to: @adapter
  defdelegate get_agent!(scope, workspace_id, agent_id), to: @adapter
  defdelegate list_agents(scope, workspace_id), to: @adapter
  defdelegate list_remote_agents(scope, workspace_id), to: @adapter
  defdelegate list_agents_paginated(scope, workspace_id), to: @adapter
  defdelegate list_agents_paginated(scope, workspace_id, opts), to: @adapter
  defdelegate list_remote_agents_paginated(scope, workspace_id, opts \\ []), to: @adapter
  defdelegate update_agent(scope, agent, attrs), to: @adapter
  defdelegate delete_agent(scope, agent), to: @adapter
  defdelegate change_agent(agent), to: @adapter
  defdelegate change_agent(agent, attrs), to: @adapter
  defdelegate change_local_agent(local_agent), to: @adapter
  defdelegate change_local_agent(local_agent, attrs), to: @adapter

  # Preloading
  defdelegate preload_agent(agent), to: @adapter

  # Internal API
  defdelegate get_agent_with_provider!(agent_id), to: @adapter
  defdelegate get_agent_name(agent_id), to: @adapter
  defdelegate failover_stats(agent_id), to: @adapter

  # Internal API (unscoped)
  defdelegate update_remote_agent_card(remote_agent, attrs), to: @adapter

  # Execution
  defdelegate execute(agent, message, opts), to: @adapter
  defdelegate execute_sync(agent, workspace_id, params), to: @adapter
  defdelegate execute_async(agent, workspace_id, params), to: @adapter

  # Linking
  defdelegate link_agents(scope, attrs), to: @adapter
  defdelegate unlink_agents(scope, manager_id, worker_id), to: @adapter
  defdelegate list_linked_workers(scope, manager_id), to: @adapter

  # Failover chain
  defdelegate list_failover_chain(agent_id), to: @adapter
  defdelegate add_failover_entry(agent_id, backup_agent_id), to: @adapter
  defdelegate remove_failover_entry(entry_id), to: @adapter
  defdelegate reorder_failover_chain(agent_id, entry_ids), to: @adapter
end
