defmodule SummonerWeb.API.V1.SkillController do
  @moduledoc "REST API controller for skills."

  use SummonerWeb, :controller

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.Skills

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  def index(conn, params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    page = Skills.list_skills_paginated(scope, workspace_id, tenant_id, pagination_opts(params))
    render(conn, :index, page: page)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    skill = Skills.get_skill!(scope, workspace_id, tenant_id, id)
    render(conn, :show, skill: skill)
  end

  def create(conn, %{"skill" => attrs}) do
    scope = conn.assigns.current_scope

    attrs =
      attrs
      |> Map.put("workspace_id", conn.assigns.current_workspace_id)
      |> Map.put("tenant_id", conn.assigns.current_tenant_id)

    case Skills.create_skill(scope, attrs) do
      {:ok, skill} ->
        conn
        |> put_status(:created)
        |> render(:show, skill: skill)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id, "skill" => attrs}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    skill = Skills.get_skill!(scope, workspace_id, tenant_id, id)

    with {:ok, skill} <- Skills.update_skill(scope, skill, attrs) do
      render(conn, :show, skill: skill)
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    skill = Skills.get_skill!(scope, workspace_id, tenant_id, id)

    with {:ok, _} <- Skills.delete_skill(scope, skill) do
      send_resp(conn, :no_content, "")
    end
  end
end
