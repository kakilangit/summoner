defmodule SummonerWeb.API.V1.PipelineController do
  @moduledoc "REST API controller for pipelines (Quests)."

  use SummonerWeb, :controller

  alias Summoner.Ports.Persistence.Pipelines

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  def index(conn, _params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    pipelines = Pipelines.list_pipelines(scope, workspace_id)
    render(conn, :index, pipelines: pipelines)
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

  def runs(conn, %{"pipeline_id" => pipeline_id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    _pipeline = Pipelines.get_pipeline!(scope, workspace_id, pipeline_id)
    runs = Pipelines.list_runs(pipeline_id)
    render(conn, :runs, runs: runs)
  end
end
