defmodule Summoner.MCP do
  @moduledoc """
  The MCP (Model Context Protocol) context.

  Manages MCP server configurations, agent-server bindings (the
  "Magic Circle" allowlist), and provides the runtime bridge for
  tool listing and execution.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Summoner.MCP.{AgentMcpServer, ClientBridge, McpServer}
  alias Summoner.Pagination
  alias Summoner.Repo

  # -------------------------------------------------------------------
  # MCP Server CRUD
  # -------------------------------------------------------------------

  @doc """
  Creates an MCP server in a workspace or tenant.
  """
  def create_server(%{user: _user}, attrs) do
    %McpServer{}
    |> McpServer.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists MCP servers for a workspace and its tenant.
  """
  def list_servers(%{user: _user}, workspace_id, tenant_id) do
    McpServer
    |> where_scope(workspace_id, tenant_id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Lists MCP servers for a workspace and its tenant with pagination.
  """
  def list_servers_paginated(%{user: _user}, workspace_id, tenant_id, opts \\ []) do
    McpServer
    |> where_scope(workspace_id, tenant_id)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets an MCP server by ID, scoped to workspace or tenant.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_server!(%{user: _user}, workspace_id, tenant_id, server_id) do
    McpServer
    |> where_scope(workspace_id, tenant_id)
    |> Repo.get!(server_id)
  end

  @doc """
  Updates an MCP server.
  """
  def update_server(%{user: _user}, %McpServer{} = server, attrs) do
    server
    |> McpServer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an MCP server.
  """
  def delete_server(%{user: _user}, %McpServer{} = server) do
    server
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.foreign_key_constraint(:agent_mcp_servers,
      name: :agent_mcp_servers_mcp_server_id_fkey,
      message: "rune is still equipped by one or more summons"
    )
    |> Repo.delete()
  end

  # -------------------------------------------------------------------
  # Equip / Unequip (Magic Circle)
  # -------------------------------------------------------------------

  @doc """
  Equips an MCP server to an Agent (adds to allowlist).
  """
  def equip_server(%{user: _user}, attrs) do
    result =
      %AgentMcpServer{}
      |> AgentMcpServer.changeset(attrs)
      |> Repo.insert()

    with {:ok, record} <- result do
      notify_tools_changed(record.agent_id)
      {:ok, record}
    end
  end

  @doc """
  Unequips an MCP server from an Agent (removes from allowlist).
  """
  def unequip_server(%{user: _user}, agent_id, mcp_server_id) do
    AgentMcpServer
    |> where([f], f.agent_id == ^agent_id and f.mcp_server_id == ^mcp_server_id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      record ->
        result = Repo.delete(record)

        with {:ok, deleted} <- result do
          notify_tools_changed(agent_id)
          {:ok, deleted}
        end
    end
  end

  @doc """
  Lists MCP servers equipped to an Agent.

  Per-agent env overrides are merged into each server's config env,
  so adapters see the combined env without any changes.
  """
  def list_equipped_servers(agent_id) do
    query =
      from s in McpServer,
        join: ams in AgentMcpServer,
        on: ams.mcp_server_id == s.id and ams.agent_id == ^agent_id,
        where: ams.enabled == true,
        order_by: [asc: s.name],
        select: {s, ams.env}

    query
    |> Repo.all()
    |> Enum.map(fn {server, agent_env} -> merge_agent_env(server, agent_env) end)
  end

  @doc """
  Lists all equipped servers for an agent, regardless of enabled state.
  Returns `{server, enabled}` tuples for the UI.
  """
  def list_all_equipped_servers(agent_id) do
    from(s in McpServer,
      join: ams in AgentMcpServer,
      on: ams.mcp_server_id == s.id and ams.agent_id == ^agent_id,
      order_by: [asc: s.name],
      select: {s, ams.enabled}
    )
    |> Repo.all()
  end

  @doc """
  Toggles the enabled state of an equipped MCP server.
  When toggled ON, starts the MCP client connection.
  When toggled OFF, stops the MCP client connection.
  Publishes `AgentConfigChanged` so the agent server reloads.
  """
  def toggle_server(%{user: _user}, workspace_id, agent_id, mcp_server_id) do
    AgentMcpServer
    |> where([ams], ams.agent_id == ^agent_id and ams.mcp_server_id == ^mcp_server_id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      record ->
        new_enabled = !record.enabled

        record
        |> AgentMcpServer.changeset(%{enabled: new_enabled})
        |> Repo.update()
        |> tap(fn
          {:ok, _} -> apply_toggle(workspace_id, agent_id, mcp_server_id, record.env, new_enabled)
          _ -> :ok
        end)
    end
  end

  defp apply_toggle(workspace_id, agent_id, mcp_server_id, agent_env, enabled) do
    Task.Supervisor.start_child(Summoner.TaskSupervisor, fn ->
      server = Repo.get!(McpServer, mcp_server_id)
      merged = merge_agent_env(server, agent_env)
      start_or_stop_client(workspace_id, merged, enabled)
      notify_tools_changed(agent_id)
    end)
  end

  defp start_or_stop_client(workspace_id, server, true) do
    case ClientBridge.start_client(workspace_id, server) do
      {:ok, _pid} ->
        Logger.info("MCP client started: #{server.name}")

      {:error, reason} ->
        Logger.error("Failed to start MCP client #{server.name}: #{inspect(reason)}")
    end
  end

  defp start_or_stop_client(workspace_id, server, false) do
    ClientBridge.stop_client(workspace_id, server)
    Logger.info("MCP client stopped: #{server.name}")
  end

  @doc """
  Gets the per-agent env overrides for a specific agent-server binding.
  """
  def get_equipped_env(agent_id, mcp_server_id) do
    AgentMcpServer
    |> where([ams], ams.agent_id == ^agent_id and ams.mcp_server_id == ^mcp_server_id)
    |> Repo.one()
  end

  @doc """
  Updates the per-agent env overrides for an equipped server.
  """
  def update_equipped_env(%{user: _user}, agent_id, mcp_server_id, env) when is_map(env) do
    AgentMcpServer
    |> where([ams], ams.agent_id == ^agent_id and ams.mcp_server_id == ^mcp_server_id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      record ->
        record
        |> AgentMcpServer.changeset(%{env: env})
        |> Repo.update()
    end
  end

  # Merges per-agent env into server.config["env"]. Agent env wins on conflicts.
  defp merge_agent_env(server, agent_env) when agent_env == %{} or is_nil(agent_env), do: server

  defp merge_agent_env(server, agent_env) do
    server_env = get_in(server.config, ["env"]) || %{}
    merged_env = Map.merge(server_env, agent_env)
    %{server | config: Map.put(server.config, "env", merged_env)}
  end

  @doc """
  Checks if an Agent is allowed to use a specific MCP server.
  """
  def server_equipped?(agent_id, mcp_server_id) do
    AgentMcpServer
    |> where([f], f.agent_id == ^agent_id and f.mcp_server_id == ^mcp_server_id)
    |> Repo.exists?()
  end

  # -------------------------------------------------------------------
  # Tool Bridge
  # -------------------------------------------------------------------

  @doc """
  Lists tools available from an MCP server.

  Connects to the server via its transport and calls `tools/list`.
  """
  def list_tools(workspace_id, %McpServer{} = server) do
    ClientBridge.list_tools(workspace_id, server)
  end

  @doc """
  Calls a tool on an MCP server.

  Connects to the server via its transport and calls `tools/call`.
  """
  def call_tool(workspace_id, %McpServer{} = server, tool_name, input) do
    ClientBridge.call_tool(workspace_id, server, tool_name, input)
  end

  @doc """
  Lists tools from all MCP servers equipped to an Agent.

  Connects to the server to fetch tools (used for eager loading).
  Returns a flat list of `%{server_id, server_name, tool}` maps.
  """
  def list_tools_for_agent(workspace_id, agent_id) do
    agent_id
    |> list_equipped_servers()
    |> Enum.flat_map(&list_tools_for_server(workspace_id, &1))
  end

  @doc """
  Lists tools only from already-running MCP clients for an agent.

  Does not start new connections. Used by the agent server to
  refresh tool definitions without triggering new MCP handshakes.
  """
  def list_tools_from_running_clients(workspace_id, agent_id) do
    agent_id
    |> list_equipped_servers()
    |> Enum.filter(&ClientBridge.client_running?(workspace_id, &1))
    |> Enum.flat_map(&list_tools_for_server(workspace_id, &1))
  end

  defp list_tools_for_server(workspace_id, server) do
    case list_tools(workspace_id, server) do
      {:ok, tools} ->
        Enum.map(tools, fn tool ->
          %{server_id: server.id, server_name: server.name, tool: tool}
        end)

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Calls a tool, enforcing the agent's allowlist.

  Returns `{:error, :not_allowed}` if the server is not equipped to the agent.
  """
  def call_tool_for_agent(workspace_id, agent_id, %McpServer{} = server, tool_name, input) do
    if server_equipped?(agent_id, server.id) do
      call_tool(workspace_id, server, tool_name, input)
    else
      {:error, :not_allowed}
    end
  end

  # -------------------------------------------------------------------
  # Tool change notifications
  # -------------------------------------------------------------------

  @doc """
  Notifies the agent server that its tool configuration has changed.

  Publishes `AgentConfigChanged` so the agent server reloads
  tool definitions from running MCP clients.
  """
  def notify_tools_changed(agent_id) do
    Summoner.Events.publish(%Summoner.Events.AgentConfigChanged{agent_id: agent_id})
  end

  # -------------------------------------------------------------------
  # Tenant-scoped operations
  # -------------------------------------------------------------------

  @doc """
  Lists MCP servers scoped to a tenant only.
  """
  def list_tenant_servers(tenant_id) do
    McpServer
    |> where([s], s.tenant_id == ^tenant_id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Lists tenant-scoped MCP servers with pagination.
  """
  def list_tenant_servers_paginated(tenant_id, opts \\ []) do
    McpServer
    |> where([s], s.tenant_id == ^tenant_id)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a tenant-scoped MCP server by ID.
  """
  def get_tenant_server!(tenant_id, id) do
    McpServer
    |> where([s], s.tenant_id == ^tenant_id)
    |> Repo.get!(id)
  end

  defp where_scope(query, workspace_id, tenant_id) do
    where(query, [s], s.workspace_id == ^workspace_id or s.tenant_id == ^tenant_id)
  end
end
