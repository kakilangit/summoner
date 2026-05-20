defmodule Summoner.Ports.Persistence.MCP do
  @moduledoc "Port for MCP persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :mcp],
             Summoner.Adapters.Persistence.MCP
           )

  # Server CRUD
  defdelegate create_server(scope, attrs), to: @adapter
  defdelegate list_servers(scope, workspace_id, tenant_id), to: @adapter
  defdelegate list_servers_paginated(scope, workspace_id, tenant_id), to: @adapter
  defdelegate list_servers_paginated(scope, workspace_id, tenant_id, opts), to: @adapter
  defdelegate get_server!(scope, workspace_id, tenant_id, server_id), to: @adapter
  defdelegate update_server(scope, server, attrs), to: @adapter
  defdelegate delete_server(scope, server), to: @adapter

  # Equip / Unequip
  defdelegate equip_server(scope, attrs), to: @adapter
  defdelegate unequip_server(scope, agent_id, mcp_server_id), to: @adapter
  defdelegate list_equipped_servers(agent_id), to: @adapter
  defdelegate list_all_equipped_servers(agent_id), to: @adapter
  defdelegate toggle_server(scope, workspace_id, agent_id, mcp_server_id), to: @adapter
  defdelegate get_equipped_env(agent_id, mcp_server_id), to: @adapter
  defdelegate update_equipped_env(scope, agent_id, mcp_server_id, env), to: @adapter
  defdelegate server_equipped?(agent_id, mcp_server_id), to: @adapter

  # Tool Bridge
  defdelegate list_tools(workspace_id, server), to: @adapter
  defdelegate call_tool(workspace_id, server, tool_name, input), to: @adapter
  defdelegate list_tools_for_agent(workspace_id, agent_id), to: @adapter
  defdelegate list_tools_from_running_clients(workspace_id, agent_id), to: @adapter
  defdelegate call_tool_for_agent(workspace_id, agent_id, server, tool_name, input), to: @adapter

  # Notifications
  defdelegate notify_tools_changed(agent_id), to: @adapter

  # Tenant-scoped
  defdelegate list_tenant_servers(tenant_id), to: @adapter
  defdelegate list_tenant_servers_paginated(tenant_id), to: @adapter
  defdelegate list_tenant_servers_paginated(tenant_id, opts), to: @adapter
  defdelegate get_tenant_server!(tenant_id, id), to: @adapter
end
