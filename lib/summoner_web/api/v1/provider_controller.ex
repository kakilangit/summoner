defmodule SummonerWeb.API.V1.ProviderController do
  @moduledoc "REST API controller for providers (Gateways)."

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.Providers
  alias SummonerWeb.API.Schemas

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  tags ["providers"]

  operation :index,
    summary: "List providers",
    parameters: [
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"Provider list", "application/json", Schemas.ProviderListResponse}]

  operation :show,
    summary: "Get provider",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Provider", "application/json", Schemas.Provider}]

  operation :create,
    summary: "Create provider",
    request_body: {"Provider params", "application/json", Schemas.ProviderParams},
    responses: [
      created: {"Provider", "application/json", Schemas.Provider},
      unprocessable_entity: {"Validation error", "application/json", Schemas.ErrorResponse}
    ]

  operation :update,
    summary: "Update provider",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Provider params", "application/json", Schemas.ProviderParams},
    responses: [ok: {"Provider", "application/json", Schemas.Provider}]

  operation :delete,
    summary: "Delete provider",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Deleted"]

  def index(conn, params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id

    page =
      Providers.list_providers_paginated(scope, workspace_id, tenant_id, pagination_opts(params))

    render(conn, :index, page: page)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    provider = Providers.get_provider!(scope, workspace_id, tenant_id, id)
    render(conn, :show, provider: provider)
  end

  def create(conn, attrs) do
    scope = conn.assigns.current_scope

    attrs =
      attrs
      |> Map.drop(["tenant_id", "workspace_id"])
      |> Map.put("workspace_id", conn.assigns.current_workspace_id)

    case Providers.create_provider(scope, attrs) do
      {:ok, provider} ->
        conn
        |> put_status(:created)
        |> render(:show, provider: provider)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    provider = Providers.get_provider!(scope, workspace_id, tenant_id, id)
    attrs = Map.drop(params, ["id"])

    with {:ok, provider} <- Providers.update_provider(scope, provider, attrs) do
      render(conn, :show, provider: provider)
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    provider = Providers.get_provider!(scope, workspace_id, tenant_id, id)

    with {:ok, _} <- Providers.delete_provider(scope, provider) do
      send_resp(conn, :no_content, "")
    end
  end
end
