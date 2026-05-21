defmodule SummonerWeb.API.V1.AdminController do
  @moduledoc "REST API controller for admin operations (requires admin scope)."

  use SummonerWeb, :controller

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.Admin
  alias Summoner.Ports.Persistence.Invitations

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "admin"
  plug SummonerWeb.Plugs.RateLimit

  # Tenants

  def list_tenants(conn, params) do
    page = Admin.list_tenants(pagination_opts(params))
    render(conn, :tenants, page: page)
  end

  # Users

  def list_users(conn, params) do
    page = Admin.list_users(pagination_opts(params))
    render(conn, :users, page: page)
  end

  def update_user(conn, %{"id" => id} = params) do
    user = Admin.get_user!(id)

    result =
      case params do
        %{"action" => "disable"} -> Admin.disable_user(user)
        %{"action" => "enable"} -> Admin.enable_user(user)
        %{"role" => role} -> Admin.update_user_role(user, role)
        _other -> {:error, :bad_request}
      end

    case result do
      {:ok, user} ->
        render(conn, :user, user: user)

      {:error, :bad_request} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "bad_request", message: "Provide action or role parameter"}})

      {:error, :root_admin_protected} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: %{code: "forbidden", message: "Cannot modify root admin"}})

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Invitations

  def list_invitations(conn, params) do
    page = Invitations.list_all_invitations(pagination_opts(params))
    render(conn, :invitations, page: page)
  end

  # Stats

  def stats(conn, _params) do
    stats = Admin.system_stats()
    render(conn, :stats, stats: stats)
  end
end
