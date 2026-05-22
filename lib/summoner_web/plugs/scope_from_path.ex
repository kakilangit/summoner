defmodule SummonerWeb.Plugs.ScopeFromPath do
  @moduledoc """
  Plug that extracts tenant_id and workspace_id from URL path params
  and assigns them to the connection.

  Replaces the implicit workspace derivation from Bearer tokens.
  All API endpoints are now explicitly scoped via URL:

      /api/v1/tenants/:tenant_id/workspaces/:workspace_id/...
  """

  import Plug.Conn

  alias Summoner.Domain.Schemas.Scope

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    tenant_id = conn.path_params["tenant_id"]
    workspace_id = conn.path_params["workspace_id"]

    conn
    |> assign(:current_tenant_id, tenant_id)
    |> assign(:current_workspace_id, workspace_id)
    |> assign(:current_scope, %Scope{user: nil})
  end
end
