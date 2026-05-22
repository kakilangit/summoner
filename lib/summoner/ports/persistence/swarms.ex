defmodule Summoner.Ports.Persistence.Swarms do
  @moduledoc "Port for Swarms persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :swarms],
             Summoner.Adapters.Persistence.Swarms
           )

  # Swarms
  defdelegate create_swarm(scope, attrs), to: @adapter
  defdelegate update_swarm(scope, swarm, attrs), to: @adapter
  defdelegate list_swarms(scope, workspace_id), to: @adapter
  defdelegate list_swarms_paginated(scope, workspace_id), to: @adapter
  defdelegate list_swarms_paginated(scope, workspace_id, opts), to: @adapter
  defdelegate get_swarm!(scope, workspace_id, swarm_id), to: @adapter
  defdelegate delete_swarm(scope, swarm), to: @adapter

  # Members
  defdelegate add_member(scope, attrs), to: @adapter
  defdelegate remove_member(scope, member), to: @adapter
  defdelegate list_members(swarm_id), to: @adapter
  defdelegate reorder_members(scope, swarm_id, member_ids), to: @adapter
  defdelegate member_query(), to: @adapter
  defdelegate preload_members(swarm), to: @adapter
  defdelegate list_peer_agent_ids(agent_id), to: @adapter

  # Conversations
  defdelegate list_swarm_conversations_paginated(scope, swarm_id), to: @adapter
  defdelegate list_swarm_conversations_paginated(scope, swarm_id, opts), to: @adapter
  defdelegate create_conversation(scope, swarm), to: @adapter
end
