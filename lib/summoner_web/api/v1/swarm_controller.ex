defmodule SummonerWeb.API.V1.SwarmController do
  @moduledoc "REST API controller for swarms (Parties)."

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.Swarms
  alias SummonerWeb.API.Schemas

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  tags ["swarms"]

  operation :index,
    summary: "List swarms",
    parameters: [
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"Swarm list", "application/json", Schemas.SwarmListResponse}]

  operation :show,
    summary: "Get swarm",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Swarm", "application/json", Schemas.SwarmResponse}]

  operation :create,
    summary: "Create swarm",
    request_body: {"Swarm params", "application/json", Schemas.SwarmParams},
    responses: [
      created: {"Swarm", "application/json", Schemas.SwarmResponse},
      unprocessable_entity: {"Validation error", "application/json", Schemas.ErrorResponse}
    ]

  operation :update,
    summary: "Update swarm",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Swarm params", "application/json", Schemas.SwarmParams},
    responses: [ok: {"Swarm", "application/json", Schemas.SwarmResponse}]

  operation :delete,
    summary: "Delete swarm",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Deleted"]

  def index(conn, params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    page = Swarms.list_swarms_paginated(scope, workspace_id, pagination_opts(params))
    render(conn, :index, page: page)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id

    swarm =
      scope
      |> Swarms.get_swarm!(workspace_id, id)
      |> Swarms.preload_members()

    render(conn, :show, swarm: swarm)
  end

  def create(conn, %{"swarm" => attrs}) do
    scope = conn.assigns.current_scope
    attrs = Map.put(attrs, "workspace_id", conn.assigns.current_workspace_id)

    case Swarms.create_swarm(scope, attrs) do
      {:ok, swarm} ->
        conn
        |> put_status(:created)
        |> render(:show, swarm: swarm)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id, "swarm" => attrs}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    swarm = Swarms.get_swarm!(scope, workspace_id, id)

    with {:ok, swarm} <- Swarms.update_swarm(scope, swarm, attrs) do
      render(conn, :show, swarm: swarm)
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    swarm = Swarms.get_swarm!(scope, workspace_id, id)

    with {:ok, _} <- Swarms.delete_swarm(scope, swarm) do
      send_resp(conn, :no_content, "")
    end
  end
end
