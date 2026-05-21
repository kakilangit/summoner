defmodule SummonerWeb.McpServerLiveTest do
  use SummonerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Summoner.Adapters.Persistence.Agents
  alias Summoner.Adapters.Persistence.MCP
  alias Summoner.Adapters.Persistence.Providers
  alias Summoner.Adapters.Persistence.Workspaces

  setup :register_and_log_in_user

  import Summoner.Adapters.Persistence.TenantsFixtures

  setup %{scope: scope} do
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
    test "lists MCP servers", %{conn: conn, scope: scope, workspace: ws} do
      {:ok, _server} =
        MCP.create_server(scope, %{
          name: "Everything Server",
          transport: :stdio,
          command_or_url: "npx -y @modelcontextprotocol/server-everything",
          workspace_id: ws.id
        })

      {:ok, _view, html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/mcp_servers")

      assert html =~ "Runes"
      assert html =~ "Everything Server"
      assert html =~ "stdio"
    end

    test "shows empty state", %{conn: conn, workspace: ws} do
      {:ok, _view, html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/mcp_servers")

      assert html =~ "No runes configured"
    end

    test "deletes a server", %{conn: conn, scope: scope, workspace: ws} do
      {:ok, mcp_server} =
        MCP.create_server(scope, %{
          name: "To Delete",
          transport: :stdio,
          command_or_url: "echo hello",
          workspace_id: ws.id
        })

      {:ok, view, _html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/mcp_servers")

      render_click(view, "delete", %{"id" => mcp_server.id})

      html = render(view)
      refute html =~ "To Delete"
    end
  end

  describe "Form - New" do
    test "creates an MCP server", %{conn: conn, workspace: ws} do
      {:ok, view, _html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/mcp_servers/new")

      view
      |> form("#mcp-server-form",
        mcp_server: %{
          name: "New Server",
          transport: "stdio",
          command_or_url: "npx -y @modelcontextprotocol/server-everything"
        }
      )
      |> render_submit()

      assert_redirect(view)
    end
  end

  describe "Form - Edit" do
    test "updates an MCP server", %{conn: conn, scope: scope, workspace: ws} do
      {:ok, server} =
        MCP.create_server(scope, %{
          name: "Old Name",
          transport: :stdio,
          command_or_url: "echo hello",
          workspace_id: ws.id
        })

      {:ok, view, html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/mcp_servers/#{server.id}/edit")

      assert html =~ "Edit Rune"

      view
      |> form("#mcp-server-form", mcp_server: %{name: "New Name"})
      |> render_submit()

      assert_redirect(view)
    end
  end

  describe "AgentLive.Tools" do
    setup %{scope: scope, workspace: ws, provider: prov} do
      {:ok, agent} =
        Agents.create_agent(scope, %{
          name: "Test Agent",
          model: "llama3",
          role: :autonomous,
          workspace_id: ws.id,
          provider_id: prov.id
        })

      {:ok, server} =
        MCP.create_server(scope, %{
          name: "Tool Server",
          transport: :stdio,
          command_or_url: "echo hello",
          workspace_id: ws.id
        })

      %{agent: agent, server: server}
    end

    test "lists available servers", %{
      conn: conn,
      workspace: ws,
      agent: fam,
      server: server
    } do
      {:ok, _view, html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/agents/#{fam.id}/mcp_servers")

      assert html =~ "Runes for #{fam.name}"
      assert html =~ server.name
      assert html =~ "Equip"
    end

    test "equips and unequips a server", %{
      conn: conn,
      workspace: ws,
      agent: fam
    } do
      {:ok, view, _html} =
        live(conn, ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/agents/#{fam.id}/mcp_servers")

      # Equip
      view |> element("button", "Equip") |> render_click()
      html = render(view)
      assert html =~ "Unequip"

      # Unequip
      view |> element("button", "Unequip") |> render_click()
      html = render(view)
      assert html =~ "Equip"
    end
  end
end
