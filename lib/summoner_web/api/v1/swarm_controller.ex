defmodule SummonerWeb.API.V1.SwarmController do
  @moduledoc "REST API controller for swarms (Parties)."

  use SummonerWeb, :controller

  alias Summoner.Ports.Persistence.Swarms

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  def index(conn, _params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    swarms = Swarms.list_swarms(scope, workspace_id)
    render(conn, :index, swarms: swarms)
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
