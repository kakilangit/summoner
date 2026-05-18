defmodule SummonerWeb.UserRegistrationControllerTest do
  use SummonerWeb.ConnCase, async: true

  import Summoner.AccountsFixtures
  import Summoner.TenantsFixtures

  defp create_open_tenant(_context) do
    scope = user_scope_fixture()
    tenant = tenant_fixture(scope)

    Summoner.Tenants.update_settings(tenant, %{registration_mode: :open})
    tenant = Summoner.Tenants.get_tenant!(tenant.id)
    %{tenant: tenant}
  end

  describe "GET /guilds/:tenant_id/register" do
    setup :create_open_tenant

    test "renders registration page for open tenant", %{conn: conn, tenant: tenant} do
      conn = get(conn, ~p"/realms/#{tenant.id}/register")
      response = html_response(conn, 200)
      assert response =~ "Register for #{tenant.name}"
      assert response =~ ~p"/users/log-in"
    end

    test "redirects if already logged in", %{conn: conn, tenant: tenant} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/realms/#{tenant.id}/register")
      assert redirected_to(conn) == ~p"/guilds"
    end

    test "redirects for disabled tenant registration", %{conn: conn} do
      scope = user_scope_fixture()
      disabled_tenant = tenant_fixture(scope)

      conn = get(conn, ~p"/realms/#{disabled_tenant.id}/register")
      assert redirected_to(conn) == ~p"/users/log-in"
      assert conn.assigns.flash["error"] =~ "disabled"
    end
  end

  describe "POST /guilds/:tenant_id/register" do
    setup :create_open_tenant

    @tag :capture_log
    test "creates account with tenant membership", %{conn: conn, tenant: tenant} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/realms/#{tenant.id}/register", %{
          "user" => valid_user_attributes(email: email)
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in"

      assert conn.assigns.flash["info"] =~
               ~r/An email was sent to .*, please access it to confirm your account/

      # Verify tenant membership was created
      user = Summoner.Accounts.get_user_by_email(email)
      assert user
      membership = Summoner.Tenants.get_membership(tenant.id, user.id)
      assert membership
      assert membership.role == :member
    end

    test "render errors for invalid data", %{conn: conn, tenant: tenant} do
      conn =
        post(conn, ~p"/realms/#{tenant.id}/register", %{
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "must have the @ sign and no spaces"
    end
  end
end
