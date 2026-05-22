defmodule SummonerWeb.API.V1.EventRuleController do
  @moduledoc "REST API controller for event rules (Omens) CRUD."

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import SummonerWeb.API.PaginationParams

  alias Summoner.Services.EventRules
  alias SummonerWeb.API.Schemas

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  tags ["event-rules"]

  operation :index,
    summary: "List event rules",
    parameters: [
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      event_type: [in: :query, schema: %OpenApiSpex.Schema{type: :string}, required: false],
      enabled: [in: :query, schema: %OpenApiSpex.Schema{type: :boolean}, required: false]
    ],
    responses: [ok: {"Event rule list", "application/json", Schemas.EventRuleListResponse}]

  operation :show,
    summary: "Get event rule",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Event rule", "application/json", Schemas.EventRule}]

  operation :create,
    summary: "Create event rule",
    request_body: {"Event rule params", "application/json", Schemas.EventRuleParams},
    responses: [
      created: {"Event rule", "application/json", Schemas.EventRule},
      unprocessable_entity: {"Validation error", "application/json", Schemas.ErrorResponse}
    ]

  operation :update,
    summary: "Update event rule",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Event rule params", "application/json", Schemas.EventRuleParams},
    responses: [ok: {"Event rule", "application/json", Schemas.EventRule}]

  operation :delete,
    summary: "Delete event rule",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Deleted"]

  operation :test,
    summary: "Dry-run test event rule conditions",
    request_body: {"Test params", "application/json", Schemas.EventRuleTestParams},
    responses: [ok: {"Test result", "application/json", Schemas.EventRuleTestResult}]

  operation :executions,
    summary: "List executions for an event rule",
    parameters: [
      event_rule_id: [in: :path, type: :string, required: true],
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [
      ok: {"Execution list", "application/json", Schemas.EventRuleExecutionListResponse}
    ]

  def index(conn, params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    opts = pagination_opts(params) ++ filter_opts(params)
    page = EventRules.list_rules_paginated(scope, workspace_id, opts)
    render(conn, :index, page: page)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    event_rule = EventRules.get_rule!(scope, workspace_id, id)
    render(conn, :show, event_rule: event_rule)
  end

  def create(conn, attrs) do
    scope = conn.assigns.current_scope
    attrs = Map.put(attrs, "workspace_id", conn.assigns.current_workspace_id)

    case EventRules.create_rule(scope, attrs) do
      {:ok, event_rule} ->
        conn
        |> put_status(:created)
        |> render(:show, event_rule: event_rule)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    event_rule = EventRules.get_rule!(scope, workspace_id, id)
    attrs = Map.drop(params, ["id"])

    with {:ok, event_rule} <- EventRules.update_rule(scope, event_rule, attrs) do
      render(conn, :show, event_rule: event_rule)
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    event_rule = EventRules.get_rule!(scope, workspace_id, id)

    with {:ok, _} <- EventRules.delete_rule(scope, event_rule) do
      send_resp(conn, :no_content, "")
    end
  end

  def test(conn, %{"conditions" => conditions, "event_data" => event_data}) do
    case EventRules.test_rule(conditions, event_data) do
      {:ok, matches} ->
        json(conn, %{matches: matches})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: to_string(reason)})
    end
  end

  def executions(conn, %{"event_rule_id" => event_rule_id} = params) do
    # Verify the rule belongs to this workspace
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    _event_rule = EventRules.get_rule!(scope, workspace_id, event_rule_id)

    page = EventRules.list_executions_paginated(event_rule_id, pagination_opts(params))
    render(conn, :executions, page: page)
  end

  defp filter_opts(params) do
    []
    |> maybe_add(:event_type, params["event_type"])
    |> maybe_add(:enabled, parse_boolean(params["enabled"]))
    |> maybe_add(:action_type, params["action_type"])
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: [{key, value} | opts]

  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(_), do: nil
end
