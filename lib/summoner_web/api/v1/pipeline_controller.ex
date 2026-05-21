defmodule SummonerWeb.API.V1.PipelineController do
  @moduledoc "REST API controller for pipelines (Quests)."

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.Pipelines
  alias SummonerWeb.API.Schemas

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  tags ["pipelines"]

  operation :index,
    summary: "List pipelines",
    parameters: [
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"Pipeline list", "application/json", Schemas.PipelineListResponse}]

  operation :show,
    summary: "Get pipeline",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Pipeline", "application/json", Schemas.PipelineResponse}]

  operation :create,
    summary: "Create pipeline",
    request_body: {"Pipeline params", "application/json", Schemas.PipelineParams},
    responses: [
      created: {"Pipeline", "application/json", Schemas.PipelineResponse},
      unprocessable_entity: {"Validation error", "application/json", Schemas.ErrorResponse}
    ]

  operation :update,
    summary: "Update pipeline",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Pipeline params", "application/json", Schemas.PipelineParams},
    responses: [ok: {"Pipeline", "application/json", Schemas.PipelineResponse}]

  operation :delete,
    summary: "Delete pipeline",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Deleted"]

  operation :runs,
    summary: "List pipeline runs",
    parameters: [
      pipeline_id: [in: :path, type: :string, required: true],
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"Run list", "application/json", Schemas.PipelineRunListResponse}]

  def index(conn, params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    page = Pipelines.list_pipelines_paginated(scope, workspace_id, pagination_opts(params))
    render(conn, :index, page: page)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    pipeline = Pipelines.get_pipeline!(scope, workspace_id, id)
    render(conn, :show, pipeline: pipeline)
  end

  def create(conn, %{"pipeline" => attrs}) do
    scope = conn.assigns.current_scope
    attrs = Map.put(attrs, "workspace_id", conn.assigns.current_workspace_id)

    case Pipelines.create_pipeline(scope, attrs) do
      {:ok, pipeline} ->
        conn
        |> put_status(:created)
        |> render(:show, pipeline: pipeline)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id, "pipeline" => attrs}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    pipeline = Pipelines.get_pipeline!(scope, workspace_id, id)

    with {:ok, pipeline} <- Pipelines.update_pipeline(scope, pipeline, attrs) do
      render(conn, :show, pipeline: pipeline)
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    pipeline = Pipelines.get_pipeline!(scope, workspace_id, id)

    with {:ok, _} <- Pipelines.delete_pipeline(scope, pipeline) do
      send_resp(conn, :no_content, "")
    end
  end

  def runs(conn, %{"pipeline_id" => pipeline_id} = params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    _pipeline = Pipelines.get_pipeline!(scope, workspace_id, pipeline_id)
    page = Pipelines.list_runs_paginated(pipeline_id, pagination_opts(params))
    render(conn, :runs, page: page)
  end
end
