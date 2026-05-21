defmodule SummonerWeb.API.V1.ProviderController do
  @moduledoc "REST API controller for providers (Gateways)."

  use SummonerWeb, :controller

  alias Summoner.Ports.Persistence.Providers

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  def index(conn, _params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    providers = Providers.list_providers(scope, workspace_id, tenant_id)
    render(conn, :index, providers: providers)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    provider = Providers.get_provider!(scope, workspace_id, tenant_id, id)
    render(conn, :show, provider: provider)
  end

  def create(conn, %{"provider" => attrs}) do
    scope = conn.assigns.current_scope

    attrs = Map.put(attrs, "workspace_id", conn.assigns.current_workspace_id)

    case Providers.create_provider(scope, attrs) do
      {:ok, provider} ->
        conn
        |> put_status(:created)
        |> render(:show, provider: provider)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id, "provider" => attrs}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    provider = Providers.get_provider!(scope, workspace_id, tenant_id, id)

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
