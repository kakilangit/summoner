defmodule SummonerWeb.API.V1.AdminController do
  @moduledoc "REST API controller for admin operations (requires admin scope)."

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.Admin
  alias Summoner.Ports.Persistence.Invitations
  alias SummonerWeb.API.Schemas

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "admin"
  plug SummonerWeb.Plugs.RateLimit

  tags ["admin"]

  operation :list_tenants,
    summary: "List tenants",
    parameters: [
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"Tenant list", "application/json", Schemas.TenantListResponse}]

  operation :list_users,
    summary: "List users",
    parameters: [
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"User list", "application/json", Schemas.UserListResponse}]

  operation :update_user,
    summary: "Update user",
    description: "Enable/disable user or change role. Root admin is protected.",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"User update params", "application/json", Schemas.UserUpdateParams},
    responses: [
      ok: {"User", "application/json", Schemas.UserResponse},
      forbidden: {"Forbidden", "application/json", Schemas.ErrorResponse},
      bad_request: {"Bad request", "application/json", Schemas.ErrorResponse}
    ]

  operation :list_invitations,
    summary: "List invitations",
    parameters: [
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"Invitation list", "application/json", Schemas.InvitationListResponse}]

  operation :stats,
    summary: "Get system stats",
    responses: [ok: {"Stats", "application/json", Schemas.StatsResponse}]

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
