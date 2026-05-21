defmodule SummonerWeb.API.V1.AgentController do
  @moduledoc "REST API controller for agents (Summons/Envoys)."

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.Agents
  alias SummonerWeb.API.Schemas

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  tags ["agents"]

  operation :index,
    summary: "List agents",
    parameters: [
      type: [
        in: :query,
        schema: %OpenApiSpex.Schema{type: :string, enum: ["local", "remote"]},
        required: false
      ],
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"Agent list", "application/json", Schemas.AgentListResponse}]

  operation :show,
    summary: "Get agent",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Agent", "application/json", Schemas.Agent},
      not_found: {"Not found", "application/json", Schemas.ErrorResponse}
    ]

  operation :create,
    summary: "Create agent",
    request_body: {"Agent params", "application/json", Schemas.AgentParams},
    responses: [
      created: {"Agent", "application/json", Schemas.Agent},
      unprocessable_entity: {"Validation error", "application/json", Schemas.ErrorResponse}
    ]

  operation :update,
    summary: "Update agent",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Agent params", "application/json", Schemas.AgentParams},
    responses: [
      ok: {"Agent", "application/json", Schemas.Agent},
      unprocessable_entity: {"Validation error", "application/json", Schemas.ErrorResponse}
    ]

  operation :delete,
    summary: "Delete agent",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Deleted"]

  def index(conn, params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    opts = pagination_opts(params)

    page =
      case params["type"] do
        "remote" -> Agents.list_remote_agents_paginated(scope, workspace_id, opts)
        _other -> Agents.list_agents_paginated(scope, workspace_id, opts)
      end

    render(conn, :index, page: page)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id

    agent =
      scope
      |> Agents.get_agent!(workspace_id, id)
      |> Agents.preload_agent()

    render(conn, :show, agent: agent)
  end

  def create(conn, attrs) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    attrs = Map.put(attrs, "workspace_id", workspace_id)

    result =
      case attrs["type"] do
        "remote" -> Agents.create_remote_agent(scope, attrs)
        _other -> Agents.create_agent(scope, attrs)
      end

    case result do
      {:ok, agent} ->
        agent = Agents.preload_agent(agent)

        conn
        |> put_status(:created)
        |> render(:show, agent: agent)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    agent = Agents.get_agent!(scope, workspace_id, id)
    attrs = Map.drop(params, ["id"])

    with {:ok, agent} <- Agents.update_agent(scope, agent, attrs) do
      agent = Agents.preload_agent(agent)
      render(conn, :show, agent: agent)
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    agent = Agents.get_agent!(scope, workspace_id, id)

    with {:ok, _agent} <- Agents.delete_agent(scope, agent) do
      send_resp(conn, :no_content, "")
    end
  end
end
