defmodule SummonerWeb.API.V1.WebhookController do
  @moduledoc "REST API controller for webhook CRUD."

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.Webhooks
  alias SummonerWeb.API.Schemas

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  tags ["webhooks"]

  operation :index,
    summary: "List webhooks",
    parameters: [
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"Webhook list", "application/json", Schemas.WebhookListResponse}]

  operation :show,
    summary: "Get webhook",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Webhook", "application/json", Schemas.Webhook}]

  operation :create,
    summary: "Create webhook",
    request_body: {"Webhook params", "application/json", Schemas.WebhookParams},
    responses: [
      created: {"Webhook", "application/json", Schemas.Webhook},
      unprocessable_entity: {"Validation error", "application/json", Schemas.ErrorResponse}
    ]

  operation :update,
    summary: "Update webhook",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Webhook params", "application/json", Schemas.WebhookParams},
    responses: [ok: {"Webhook", "application/json", Schemas.Webhook}]

  operation :delete,
    summary: "Delete webhook",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Deleted"]

  def index(conn, params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    page = Webhooks.list_webhooks_paginated(scope, workspace_id, pagination_opts(params))
    render(conn, :index, page: page)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    webhook = Webhooks.get_webhook!(scope, workspace_id, id)
    render(conn, :show, webhook: webhook)
  end

  def create(conn, attrs) do
    scope = conn.assigns.current_scope
    attrs = Map.put(attrs, "workspace_id", conn.assigns.current_workspace_id)

    case Webhooks.create_webhook(scope, attrs) do
      {:ok, webhook} ->
        conn
        |> put_status(:created)
        |> render(:show, webhook: webhook)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    webhook = Webhooks.get_webhook!(scope, workspace_id, id)
    attrs = Map.drop(params, ["id"])

    with {:ok, webhook} <- Webhooks.update_webhook(scope, webhook, attrs) do
      render(conn, :show, webhook: webhook)
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    webhook = Webhooks.get_webhook!(scope, workspace_id, id)

    with {:ok, _} <- Webhooks.delete_webhook(scope, webhook) do
      send_resp(conn, :no_content, "")
    end
  end
end
