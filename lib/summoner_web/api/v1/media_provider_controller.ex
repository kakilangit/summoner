defmodule SummonerWeb.API.V1.MediaProviderController do
  @moduledoc "REST API controller for media providers."

  use SummonerWeb, :controller

  alias Summoner.Ports.Persistence.MediaProviders

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  def index(conn, _params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    providers = MediaProviders.list_media_providers(scope, workspace_id, tenant_id)
    render(conn, :index, media_providers: providers)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    provider = MediaProviders.get_media_provider!(scope, workspace_id, tenant_id, id)
    render(conn, :show, media_provider: provider)
  end

  def create(conn, %{"media_provider" => attrs}) do
    scope = conn.assigns.current_scope

    attrs =
      attrs
      |> Map.put("workspace_id", conn.assigns.current_workspace_id)
      |> Map.put("tenant_id", conn.assigns.current_tenant_id)

    case MediaProviders.create_media_provider(scope, attrs) do
      {:ok, provider} ->
        conn
        |> put_status(:created)
        |> render(:show, media_provider: provider)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id, "media_provider" => attrs}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    provider = MediaProviders.get_media_provider!(scope, workspace_id, tenant_id, id)

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
