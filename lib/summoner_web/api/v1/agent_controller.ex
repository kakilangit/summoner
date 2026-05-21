defmodule SummonerWeb.API.V1.AgentController do
  @moduledoc "REST API controller for agents (Summons/Envoys)."

  use SummonerWeb, :controller

  alias Summoner.Ports.Persistence.Agents

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  def index(conn, params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id

    agents =
      case params["type"] do
        "remote" -> Agents.list_remote_agents(scope, workspace_id)
        _other -> Agents.list_agents(scope, workspace_id)
      end

    render(conn, :index, agents: agents)
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

  def create(conn, %{"agent" => attrs}) do
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

  def update(conn, %{"id" => id, "agent" => attrs}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    agent = Agents.get_agent!(scope, workspace_id, id)

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
