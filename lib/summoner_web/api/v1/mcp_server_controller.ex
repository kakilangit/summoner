defmodule SummonerWeb.API.V1.McpServerController do
  @moduledoc "REST API controller for MCP servers."

  use SummonerWeb, :controller

  alias Summoner.Ports.Persistence.MCP

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  def index(conn, _params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    servers = MCP.list_servers(scope, workspace_id, tenant_id)
    render(conn, :index, servers: servers)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    server = MCP.get_server!(scope, workspace_id, tenant_id, id)
    render(conn, :show, server: server)
  end

  def create(conn, %{"mcp_server" => attrs}) do
    scope = conn.assigns.current_scope

    attrs =
      attrs
      |> Map.put("workspace_id", conn.assigns.current_workspace_id)
      |> Map.put("tenant_id", conn.assigns.current_tenant_id)

    case MCP.create_server(scope, attrs) do
      {:ok, server} ->
        conn
        |> put_status(:created)
        |> render(:show, server: server)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id, "mcp_server" => attrs}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    server = MCP.get_server!(scope, workspace_id, tenant_id, id)

    with {:ok, server} <- MCP.update_server(scope, server, attrs) do
      render(conn, :show, server: server)
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    server = MCP.get_server!(scope, workspace_id, tenant_id, id)

    with {:ok, _} <- MCP.delete_server(scope, server) do
      send_resp(conn, :no_content, "")
    end
  end
end
