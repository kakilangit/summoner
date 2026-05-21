defmodule SummonerWeb.AccessTokenLiveTest do
  use SummonerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Summoner.Adapters.Persistence.AccessTokensFixtures
  import Summoner.Adapters.Persistence.TenantsFixtures

  alias Summoner.Adapters.Persistence.Workspaces

  setup :register_and_log_in_user

  setup %{scope: scope} do
    tenant = tenant_fixture(scope)
    {:ok, workspace} = Workspaces.create_workspace(scope, tenant.id, %{name: "Test WS"})
    %{workspace: workspace}
  end

  describe "Index" do
    test "lists tokens", %{conn: conn, workspace: ws} do
      token = access_token_fixture(ws.id, %{label: "My API Key"})

      {:ok, _view, html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/access-tokens")

      assert html =~ "Wards"
      assert html =~ token.label
    end

    test "shows empty state when no tokens", %{conn: conn, workspace: ws} do
      {:ok, _view, html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/access-tokens")

      assert html =~ "No tokens yet"
    end

    test "shows New Ward link", %{conn: conn, workspace: ws} do
      {:ok, _view, html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/access-tokens")

      assert html =~ "New Ward"
    end

    test "revokes a token", %{conn: conn, workspace: ws} do
      token = access_token_fixture(ws.id, %{label: "Revokable"})

      {:ok, view, _html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/access-tokens")

      render_click(view, "revoke", %{"id" => token.id})

      html = render(view)
      assert html =~ "Token revoked."
    end
  end

  describe "Show" do
    test "shows token details", %{conn: conn, workspace: ws} do
      token = access_token_fixture(ws.id, %{label: "Detail Token", scopes: ["api", "mcp"]})

      {:ok, _view, html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/access-tokens/#{token.id}")

      assert html =~ "Detail Token"
      assert html =~ "api"
      assert html =~ "mcp"
    end

    test "shows active status badge", %{conn: conn, workspace: ws} do
      token = access_token_fixture(ws.id)

      {:ok, _view, html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/access-tokens/#{token.id}")

      assert html =~ "active"
    end

    test "has edit link", %{conn: conn, workspace: ws} do
      token = access_token_fixture(ws.id)

      {:ok, _view, html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/access-tokens/#{token.id}")

      assert html =~ "Edit"
    end
  end

  describe "Form - New" do
    test "renders new form", %{conn: conn, workspace: ws} do
      {:ok, _view, html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/access-tokens/new")

      assert html =~ "New Ward"
    end

    test "creates a token and shows plaintext", %{conn: conn, workspace: ws} do
      {:ok, view, _html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/access-tokens/new")

      view
      |> form("#token-form",
        token: %{
          label: "Fresh Token",
          scopes: ["api"],
          rate_limit_rpm: 50
        }
      )
      |> render_submit()

      html = render(view)
      assert html =~ "Copy now"
      assert html =~ "Ward created"
    end
  end

  describe "Form - Edit" do
    test "renders edit form with existing values", %{conn: conn, workspace: ws} do
      token = access_token_fixture(ws.id, %{label: "Editable"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/access-tokens/#{token.id}/edit"
        )

      assert html =~ "Edit Ward"
      assert html =~ "Editable"
    end

    test "updates token label", %{conn: conn, workspace: ws} do
      token = access_token_fixture(ws.id, %{label: "Old Label"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/access-tokens/#{token.id}/edit"
        )

      view
      |> form("#token-form", token: %{label: "New Label"})
      |> render_submit()

      assert_redirect(view)
    end
  end
end
