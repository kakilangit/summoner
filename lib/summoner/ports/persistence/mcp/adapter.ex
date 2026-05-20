defmodule Summoner.Ports.Persistence.MCP.Adapter do
  @moduledoc "Behaviour for MCP persistence operations."

  alias Summoner.Domain.Schemas.{AgentMcpServer, McpServer}

  # Server CRUD
  @callback create_server(map(), map()) :: {:ok, McpServer.t()} | {:error, Ecto.Changeset.t()}
  @callback list_servers(map(), String.t(), String.t()) :: [McpServer.t()]
  @callback list_servers_paginated(map(), String.t(), String.t()) :: struct()
  @callback list_servers_paginated(map(), String.t(), String.t(), keyword()) :: struct()
  @callback get_server!(map(), String.t(), String.t(), String.t()) :: McpServer.t()
  @callback update_server(map(), McpServer.t(), map()) ::
              {:ok, McpServer.t()} | {:error, Ecto.Changeset.t()}
  @callback delete_server(map(), McpServer.t()) ::
              {:ok, McpServer.t()} | {:error, Ecto.Changeset.t()}

  # Equip / Unequip
  @callback equip_server(map(), map()) :: {:ok, AgentMcpServer.t()} | {:error, Ecto.Changeset.t()}
  @callback unequip_server(map(), String.t(), String.t()) ::
              {:ok, AgentMcpServer.t()} | {:error, term()}
  @callback list_equipped_servers(String.t()) :: [McpServer.t()]
  @callback list_all_equipped_servers(String.t()) :: [{McpServer.t(), boolean()}]
  @callback toggle_server(map(), String.t(), String.t(), String.t()) ::
              {:ok, AgentMcpServer.t()} | {:error, term()}
  @callback get_equipped_env(String.t(), String.t()) :: AgentMcpServer.t() | nil
  @callback update_equipped_env(map(), String.t(), String.t(), map()) ::
              {:ok, AgentMcpServer.t()} | {:error, term()}
  @callback server_equipped?(String.t(), String.t()) :: boolean()

  # Tool Bridge
  @callback list_tools(String.t(), McpServer.t()) :: {:ok, [map()]} | {:error, term()}
  @callback call_tool(String.t(), McpServer.t(), String.t(), map()) ::
              {:ok, term()} | {:error, term()}
  @callback list_tools_for_agent(String.t(), String.t()) :: [map()]
  @callback list_tools_from_running_clients(String.t(), String.t()) :: [map()]
  @callback call_tool_for_agent(
              String.t(),
              String.t(),
              McpServer.t(),
              String.t(),
              map()
            ) :: {:ok, term()} | {:error, term()}

  # Notifications
  @callback notify_tools_changed(String.t()) :: :ok

  # Tenant-scoped
  @callback list_tenant_servers(String.t()) :: [McpServer.t()]
  @callback list_tenant_servers_paginated(String.t()) :: struct()
  @callback list_tenant_servers_paginated(String.t(), keyword()) :: struct()
  @callback get_tenant_server!(String.t(), String.t()) :: McpServer.t()
end
