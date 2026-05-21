defmodule SummonerWeb.API.V1.SecretController do
  @moduledoc "REST API controller for secrets."

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.Secrets
  alias SummonerWeb.API.Schemas

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  tags ["secrets"]

  operation :index,
    summary: "List secrets",
    parameters: [
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"Secret list", "application/json", Schemas.SecretListResponse}]

  operation :show,
    summary: "Get secret",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Secret", "application/json", Schemas.SecretResponse}]

  operation :create,
    summary: "Create secret",
    request_body: {"Secret params", "application/json", Schemas.SecretParams},
    responses: [
      created: {"Secret", "application/json", Schemas.SecretResponse},
      unprocessable_entity: {"Validation error", "application/json", Schemas.ErrorResponse}
    ]

  operation :update,
    summary: "Update secret",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Secret params", "application/json", Schemas.SecretParams},
    responses: [ok: {"Secret", "application/json", Schemas.SecretResponse}]

  operation :delete,
    summary: "Delete secret",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Deleted"]

  def index(conn, params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    page = Secrets.list_secrets_paginated(scope, workspace_id, tenant_id, pagination_opts(params))
    render(conn, :index, page: page)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    secret = Secrets.get_secret!(scope, workspace_id, tenant_id, id)
    render(conn, :show, secret: secret)
  end

  def create(conn, %{"secret" => attrs}) do
    scope = conn.assigns.current_scope

    attrs =
      attrs
      |> Map.put("workspace_id", conn.assigns.current_workspace_id)
      |> Map.put("tenant_id", conn.assigns.current_tenant_id)

    case Secrets.create_secret(scope, attrs) do
      {:ok, secret} ->
        conn
        |> put_status(:created)
        |> render(:show, secret: secret)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id, "secret" => attrs}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    secret = Secrets.get_secret!(scope, workspace_id, tenant_id, id)

    with {:ok, secret} <- Secrets.update_secret(scope, secret, attrs) do
      render(conn, :show, secret: secret)
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    secret = Secrets.get_secret!(scope, workspace_id, tenant_id, id)

    with {:ok, _} <- Secrets.delete_secret(scope, secret) do
      send_resp(conn, :no_content, "")
    end
  end
end
