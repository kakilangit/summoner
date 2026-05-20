defmodule SummonerWeb.WorkspaceLiveTest do
  use SummonerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Summoner.Adapters.Persistence.Workspaces

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.TenantsFixtures

  setup :register_and_log_in_user

  # -------------------------------------------------------------------
  # Index
  # -------------------------------------------------------------------

  describe "Index" do
    test "lists user's workspaces", %{conn: conn, scope: scope} do
      tenant = tenant_fixture(scope)
      {:ok, ws} = Workspaces.create_workspace(scope, tenant.id, %{name: "Test Workspace"})
      {:ok, _view, html} = live(conn, ~p"/guilds/#{tenant.id}/realms")

      assert html =~ "Realms"
      assert html =~ ws.name
    end

    test "shows empty state when no workspaces", %{conn: conn, scope: scope} do
      tenant = tenant_fixture(scope)
      {:ok, _view, html} = live(conn, ~p"/guilds/#{tenant.id}/realms")

      assert html =~ "No realms yet"
    end

    test "links to new workspace form", %{conn: conn, scope: scope} do
      tenant = tenant_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/guilds/#{tenant.id}/realms")

      assert view
             |> element("a", "New Realm")
             |> has_element?()
    end
  end

  # -------------------------------------------------------------------
  # New
  # -------------------------------------------------------------------

  describe "New" do
    test "creates a workspace", %{conn: conn, scope: scope} do
      tenant = tenant_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/guilds/#{tenant.id}/realms/new")

      view
      |> form("#workspace-form", workspace: %{name: "My Workspace"})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/realms/"
      assert path =~ "/realms/"
    end

    test "validates workspace name", %{conn: conn, scope: scope} do
      tenant = tenant_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/guilds/#{tenant.id}/realms/new")

      html =
        view
        |> form("#workspace-form", workspace: %{name: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end
  end

  # -------------------------------------------------------------------
  # Show
  # -------------------------------------------------------------------

  describe "Show" do
    setup %{scope: scope} do
      tenant = tenant_fixture(scope)
      {:ok, workspace} = Workspaces.create_workspace(scope, tenant.id, %{name: "Test WS"})
      %{workspace: workspace, tenant: tenant}
    end

    test "displays workspace dashboard", %{conn: conn, workspace: ws} do
      {:ok, _view, html} = live(conn, ~p"/guilds/#{ws.tenant_id}/realms/#{ws.id}")

      assert html =~ ws.name
      assert html =~ "Summons"
      assert html =~ "Channels"
      assert html =~ "Gateways"
      assert html =~ "Runes"
    end

    test "redirects for non-member workspace", %{conn: conn} do
      other_scope = user_scope_fixture()
      other_tenant = tenant_fixture(other_scope)

      {:ok, other_ws} =
        Workspaces.create_workspace(other_scope, other_tenant.id, %{name: "Other WS"})

      assert {:error, {:redirect, %{to: "/guilds"}}} =
               live(conn, ~p"/guilds/#{other_ws.tenant_id}/realms/#{other_ws.id}")
    end
  end

  # -------------------------------------------------------------------
  # Settings
  # -------------------------------------------------------------------

  describe "Settings" do
    setup %{scope: scope} do
      tenant = tenant_fixture(scope)
      {:ok, workspace} = Workspaces.create_workspace(scope, tenant.id, %{name: "Test WS"})
      %{workspace: workspace, tenant: tenant}
    end

    test "displays settings form", %{conn: conn, workspace: ws} do
      {:ok, _view, html} = live(conn, ~p"/guilds/#{ws.tenant_id}/realms/#{ws.id}/settings")

      assert html =~ "Settings"
      assert html =~ "Context Window"
    end

    test "updates settings", %{conn: conn, workspace: ws} do
      {:ok, view, _html} = live(conn, ~p"/guilds/#{ws.tenant_id}/realms/#{ws.id}/settings")

      view
      |> form("#settings-form", workspace_settings: %{context_window_messages: 30})
      |> render_submit()

      assert_redirect(view, ~p"/guilds/#{ws.tenant_id}/realms/#{ws.id}")
    end
  end

  # -------------------------------------------------------------------
  # Members
  # -------------------------------------------------------------------

  describe "Members" do
    setup %{scope: scope} do
      tenant = tenant_fixture(scope)
      {:ok, workspace} = Workspaces.create_workspace(scope, tenant.id, %{name: "Test WS"})
      %{workspace: workspace, tenant: tenant}
    end

    test "displays workspace members", %{conn: conn, workspace: ws, user: user} do
      {:ok, _view, html} = live(conn, ~p"/guilds/#{ws.tenant_id}/realms/#{ws.id}/members")

      assert html =~ "Members"
      assert html =~ user.email
      assert html =~ "admin"
    end
  end

  # -------------------------------------------------------------------
  # Auth
  # -------------------------------------------------------------------

  describe "authentication" do
    test "redirects to login when not authenticated" do
      conn = Phoenix.ConnTest.build_conn()

      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/guilds")
    end
  end
end
