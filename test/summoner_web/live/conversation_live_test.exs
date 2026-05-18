defmodule SummonerWeb.ConversationLiveTest do
  use SummonerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Summoner.Agents
  alias Summoner.Conversations
  alias Summoner.Providers
  alias Summoner.Workspaces

  setup :register_and_log_in_user

  import Summoner.TenantsFixtures

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

    {:ok, agent} =
      Agents.create_agent(scope, %{
        name: "Test Agent",
        model: "llama3",
        role: :autonomous,
        workspace_id: workspace.id,
        provider_id: provider.id
      })

    %{workspace: workspace, provider: provider, agent: agent}
  end

  describe "Index" do
    test "lists conversations", %{conn: conn, scope: scope, workspace: ws, agent: fam} do
      {:ok, _conv} =
        Conversations.create_conversation(scope, %{
          workspace_id: ws.id,
          primary_agent_id: fam.id,
          title: "Hello World"
        })

      {:ok, _view, html} = live(conn, ~p"/guilds/#{ws.tenant_id}/realms/#{ws.id}/channels")

      assert html =~ "Channels"
      assert html =~ "Hello World"
    end

    test "shows empty state", %{conn: conn, workspace: ws} do
      {:ok, _view, html} = live(conn, ~p"/guilds/#{ws.tenant_id}/realms/#{ws.id}/channels")

      assert html =~ "No channels yet"
    end

    test "creates a new conversation", %{conn: conn, workspace: ws, agent: fam} do
      {:ok, view, _html} = live(conn, ~p"/guilds/#{ws.tenant_id}/realms/#{ws.id}/channels")

      view |> element("button", "New Channel") |> render_click()

      html = render(view)
      assert html =~ fam.name

      view
      |> element("button", fam.name)
      |> render_click()

      assert_redirect(view)
    end
  end

  describe "Show" do
    test "displays conversation messages", %{
      conn: conn,
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      {:ok, conv} =
        Conversations.create_conversation(scope, %{
          workspace_id: ws.id,
          primary_agent_id: fam.id,
          title: "Test Chat"
        })

      {:ok, _msg} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :user,
          content: "Hello there!"
        })

      {:ok, _msg} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :assistant,
          content: "Hi! How can I help?",
          agent_id: fam.id
        })

      {:ok, _view, html} =
        live(conn, ~p"/guilds/#{ws.tenant_id}/realms/#{ws.id}/channels/#{conv.id}")

      assert html =~ "Test Chat"
      assert html =~ "Hello there!"
      assert html =~ "Hi! How can I help?"
    end

    test "shows empty conversation prompt", %{
      conn: conn,
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      {:ok, conv} =
        Conversations.create_conversation(scope, %{
          workspace_id: ws.id,
          primary_agent_id: fam.id,
          title: "Empty Chat"
        })

      {:ok, _view, html} =
        live(conn, ~p"/guilds/#{ws.tenant_id}/realms/#{ws.id}/channels/#{conv.id}")

      assert html =~ "Begin one to commune"
    end
  end
end
