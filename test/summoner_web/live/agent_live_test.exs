defmodule SummonerWeb.AgentLiveTest do
  use SummonerWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias Summoner.Adapters.Persistence.Agents
  alias Summoner.Adapters.Persistence.Providers
  alias Summoner.Adapters.Persistence.Workspaces

  setup :register_and_log_in_user
  setup :verify_on_exit!

  import Summoner.Adapters.Persistence.TenantsFixtures

  setup %{scope: scope} do
    # Stub model listing for all tests — mount loads models on edit
    stub(Summoner.Ports.HTTPClientMock, :get, fn _url, _opts ->
      {:ok, %{status: 200, body: %{"data" => [%{"id" => "llama3"}]}}}
    end)

    tenant = tenant_fixture(scope)
    {:ok, workspace} = Workspaces.create_workspace(scope, tenant.id, %{name: "Test WS"})

    {:ok, provider} =
      Providers.create_provider(scope, %{
        name: "Test Provider",
        kind: "ollama",
        api_format: :openai,
        type: :local,
        base_url: "http://localhost:11434",
        workspace_id: workspace.id
      })

    %{workspace: workspace, provider: provider}
  end

  describe "Index" do
    test "lists summons", %{conn: conn, scope: scope, workspace: ws, provider: prov} do
      {:ok, _fam} =
        Agents.create_agent(scope, %{
          name: "My Agent",
          model: "llama3",
          role: :autonomous,
          workspace_id: ws.id,
          provider_id: prov.id
        })

      {:ok, _view, html} = live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/agents")

      assert html =~ "Summons"
      assert html =~ "My Agent"
      assert html =~ "autonomous"
    end

    test "shows empty state", %{conn: conn, workspace: ws} do
      {:ok, _view, html} = live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/agents")

      assert html =~ "No summons yet"
    end

    test "deletes a summon", %{conn: conn, scope: scope, workspace: ws, provider: prov} do
      {:ok, agent} =
        Agents.create_agent(scope, %{
          name: "To Delete",
          model: "llama3",
          role: :autonomous,
          workspace_id: ws.id,
          provider_id: prov.id
        })

      {:ok, view, _html} = live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/agents")

      render_click(view, "delete", %{"id" => agent.id})

      html = render(view)
      refute html =~ "To Delete"
    end
  end

  describe "Form - New" do
    test "creates a summon", %{conn: conn, workspace: ws, provider: prov} do
      {:ok, view, _html} = live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/agents/new")

      view
      |> form("#agent-form",
        agent: %{
          name: "New Agent",
          role: "autonomous",
          provider_id: prov.id,
          model: "llama3"
        }
      )
      |> render_submit()

      assert_redirect(view)
    end

    test "validates summon form", %{conn: conn, workspace: ws} do
      {:ok, view, _html} = live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/agents/new")

      html =
        view
        |> form("#agent-form", agent: %{name: ""})
        |> render_change()

      assert html =~ "can"
    end
  end

  describe "Form - Edit" do
    test "updates a summon", %{conn: conn, scope: scope, workspace: ws, provider: prov} do
      {:ok, agent} =
        Agents.create_agent(scope, %{
          name: "Old Name",
          model: "llama3",
          role: :autonomous,
          workspace_id: ws.id,
          provider_id: prov.id
        })

      {:ok, view, html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/agents/#{agent.id}/edit")

      assert html =~ "Edit Summon"

      view
      |> form("#agent-form", agent: %{name: "New Name"})
      |> render_submit()

      assert_redirect(view)
    end
  end
end
