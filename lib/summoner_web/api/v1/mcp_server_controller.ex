defmodule SummonerWeb.API.V1.McpServerController do
  @moduledoc "REST API controller for MCP servers."

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.MCP
  alias SummonerWeb.API.Schemas

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  tags ["mcp-servers"]

  operation :index,
    summary: "List MCP servers",
    parameters: [
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"MCP server list", "application/json", Schemas.McpServerListResponse}]

  operation :show,
    summary: "Get MCP server",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"MCP server", "application/json", Schemas.McpServer}]

  operation :create,
    summary: "Create MCP server",
    request_body: {"MCP server params", "application/json", Schemas.McpServerParams},
    responses: [
      created: {"MCP server", "application/json", Schemas.McpServer},
      unprocessable_entity: {"Validation error", "application/json", Schemas.ErrorResponse}
    ]

  operation :update,
    summary: "Update MCP server",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"MCP server params", "application/json", Schemas.McpServerParams},
    responses: [ok: {"MCP server", "application/json", Schemas.McpServer}]

  operation :delete,
    summary: "Delete MCP server",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Deleted"]

  def index(conn, params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    page = MCP.list_servers_paginated(scope, workspace_id, tenant_id, pagination_opts(params))
    render(conn, :index, page: page)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    server = MCP.get_server!(scope, workspace_id, tenant_id, id)
    render(conn, :show, server: server)
  end

  def create(conn, attrs) do
    scope = conn.assigns.current_scope

    attrs =
      attrs
      |> Map.drop(["tenant_id", "workspace_id"])
      |> Map.put("workspace_id", conn.assigns.current_workspace_id)

    case MCP.create_server(scope, attrs) do
      {:ok, server} ->
        conn
        |> put_status(:created)
        |> render(:show, server: server)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    server = MCP.get_server!(scope, workspace_id, tenant_id, id)
    attrs = Map.drop(params, ["id"])

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
