defmodule SummonerWeb.API.V1.MediaProviderController do
  @moduledoc "REST API controller for media providers."

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.MediaProviders
  alias SummonerWeb.API.Schemas

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  tags ["media-providers"]

  operation :index,
    summary: "List media providers",
    parameters: [
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [
      ok: {"Media provider list", "application/json", Schemas.MediaProviderListResponse}
    ]

  operation :show,
    summary: "Get media provider",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Media provider", "application/json", Schemas.MediaProvider}]

  operation :create,
    summary: "Create media provider",
    request_body: {"Media provider params", "application/json", Schemas.MediaProviderParams},
    responses: [
      created: {"Media provider", "application/json", Schemas.MediaProvider},
      unprocessable_entity: {"Validation error", "application/json", Schemas.ErrorResponse}
    ]

  operation :update,
    summary: "Update media provider",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Media provider params", "application/json", Schemas.MediaProviderParams},
    responses: [ok: {"Media provider", "application/json", Schemas.MediaProvider}]

  operation :delete,
    summary: "Delete media provider",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Deleted"]

  def index(conn, params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id

    page =
      MediaProviders.list_media_providers_paginated(
        scope,
        workspace_id,
        tenant_id,
        pagination_opts(params)
      )

    render(conn, :index, page: page)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    provider = MediaProviders.get_media_provider!(scope, workspace_id, tenant_id, id)
    render(conn, :show, media_provider: provider)
  end

  def create(conn, attrs) do
    scope = conn.assigns.current_scope

    attrs =
      attrs
      |> Map.drop(["tenant_id", "workspace_id"])
      |> Map.put("workspace_id", conn.assigns.current_workspace_id)

    case MediaProviders.create_media_provider(scope, attrs) do
      {:ok, provider} ->
        conn
        |> put_status(:created)
        |> render(:show, media_provider: provider)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    provider = MediaProviders.get_media_provider!(scope, workspace_id, tenant_id, id)
    attrs = Map.drop(params, ["id"])

    with {:ok, provider} <- MediaProviders.update_media_provider(scope, provider, attrs) do
      render(conn, :show, media_provider: provider)
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    provider = MediaProviders.get_media_provider!(scope, workspace_id, tenant_id, id)

    with {:ok, _} <- MediaProviders.delete_media_provider(scope, provider) do
      send_resp(conn, :no_content, "")
    end
  end
end
