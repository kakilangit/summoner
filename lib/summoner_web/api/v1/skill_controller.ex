defmodule SummonerWeb.API.V1.SkillController do
  @moduledoc "REST API controller for skills."

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.Skills
  alias SummonerWeb.API.Schemas

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  tags ["skills"]

  operation :index,
    summary: "List skills",
    parameters: [
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"Skill list", "application/json", Schemas.SkillListResponse}]

  operation :show,
    summary: "Get skill",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Skill", "application/json", Schemas.Skill}]

  operation :create,
    summary: "Create skill",
    request_body: {"Skill params", "application/json", Schemas.SkillParams},
    responses: [
      created: {"Skill", "application/json", Schemas.Skill},
      unprocessable_entity: {"Validation error", "application/json", Schemas.ErrorResponse}
    ]

  operation :update,
    summary: "Update skill",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Skill params", "application/json", Schemas.SkillParams},
    responses: [ok: {"Skill", "application/json", Schemas.Skill}]

  operation :delete,
    summary: "Delete skill",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Deleted"]

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

  def create(conn, attrs) do
    scope = conn.assigns.current_scope

    attrs =
      attrs
      |> Map.drop(["tenant_id", "workspace_id"])
      |> Map.put("workspace_id", conn.assigns.current_workspace_id)

    case Skills.create_skill(scope, attrs) do
      {:ok, skill} ->
        conn
        |> put_status(:created)
        |> render(:show, skill: skill)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    skill = Skills.get_skill!(scope, workspace_id, tenant_id, id)
    attrs = Map.drop(params, ["id"])

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
