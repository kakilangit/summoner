defmodule SummonerWeb.ProviderLiveTest do
  use SummonerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Summoner.Providers
  alias Summoner.Workspaces

  setup :register_and_log_in_user

  import Summoner.TenantsFixtures

  setup %{scope: scope} do
    tenant = tenant_fixture(scope)
    {:ok, workspace} = Workspaces.create_workspace(scope, tenant.id, %{name: "Test WS"})
    %{workspace: workspace}
  end

  describe "Index" do
    test "lists providers", %{conn: conn, scope: scope, workspace: ws} do
      {:ok, _provider} =
        Providers.create_provider(scope, %{
          name: "My Ollama",
          kind: "ollama",
          api_format: :openai,
          type: :local,
          base_url: "http://localhost:11434",
          workspace_id: ws.id
        })

      {:ok, _view, html} = live(conn, ~p"/realms/#{ws.tenant_id}/realms/#{ws.id}/gateways")

      assert html =~ "Gateways"
      assert html =~ "My Ollama"
      assert html =~ "Ollama"
    end

    test "shows empty state", %{conn: conn, workspace: ws} do
      {:ok, _view, html} = live(conn, ~p"/realms/#{ws.tenant_id}/realms/#{ws.id}/gateways")

      assert html =~ "No vessels configured"
    end

    test "deletes a provider", %{conn: conn, scope: scope, workspace: ws} do
      {:ok, provider} =
        Providers.create_provider(scope, %{
          name: "To Delete",
          kind: "ollama",
          api_format: :openai,
          type: :local,
          base_url: "http://localhost:11434",
          workspace_id: ws.id
        })

      {:ok, view, _html} = live(conn, ~p"/realms/#{ws.tenant_id}/realms/#{ws.id}/gateways")

      render_click(view, "delete", %{"id" => provider.id})

      html = render(view)
      refute html =~ "To Delete"
    end
  end

  describe "Form - New" do
    test "creates a provider", %{conn: conn, workspace: ws} do
      {:ok, view, _html} = live(conn, ~p"/realms/#{ws.tenant_id}/realms/#{ws.id}/gateways/new")

      view
      |> form("#provider-form",
        provider: %{
          name: "New Provider",
          kind: "ollama",
          api_format: "openai",
          type: "local",
          base_url: "http://localhost:11434"
        }
      )
      |> render_submit()

      assert_redirect(view)
    end

    test "validates provider form", %{conn: conn, workspace: ws} do
      {:ok, view, _html} = live(conn, ~p"/realms/#{ws.tenant_id}/realms/#{ws.id}/gateways/new")

      html =
        view
        |> form("#provider-form", provider: %{name: ""})
        |> render_change()

      # "can't be blank" or "can&#39;t be blank"
      assert html =~ "can"
    end
  end

  describe "Form - Edit" do
    test "updates a provider", %{conn: conn, scope: scope, workspace: ws} do
      {:ok, provider} =
        Providers.create_provider(scope, %{
          name: "Old Name",
          kind: "ollama",
          api_format: :openai,
          type: :local,
          base_url: "http://localhost:11434",
          workspace_id: ws.id
        })

      {:ok, view, html} =
        live(conn, ~p"/realms/#{ws.tenant_id}/realms/#{ws.id}/gateways/#{provider.id}/edit")

      assert html =~ "Edit Gateway"

      view
      |> form("#provider-form", provider: %{name: "New Name"})
      |> render_submit()

      assert_redirect(view)
    end
  end
end
