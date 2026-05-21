defmodule SummonerWeb.API.V1.SecretController do
  @moduledoc "REST API controller for secrets."

  use SummonerWeb, :controller

  alias Summoner.Ports.Persistence.Secrets

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  def index(conn, _params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    tenant_id = conn.assigns.current_tenant_id
    secrets = Secrets.list_secrets(scope, workspace_id, tenant_id)
    render(conn, :index, secrets: secrets)
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
