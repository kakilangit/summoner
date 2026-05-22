defmodule SummonerWeb.AgentLive.MemoriesTest do
  use SummonerWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias Summoner.Adapters.Persistence.Agents
  alias Summoner.Adapters.Persistence.Providers
  alias Summoner.Adapters.Persistence.Workspaces

  import Summoner.Adapters.Persistence.AgentMemoriesFixtures
  import Summoner.Adapters.Persistence.TenantsFixtures

  setup :register_and_log_in_user
  setup :verify_on_exit!

  setup %{scope: scope} do
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

    {:ok, agent} =
      Agents.create_agent(scope, %{
        name: "Memory Agent",
        model: "llama3",
        role: :autonomous,
        workspace_id: workspace.id,
        provider_id: provider.id
      })

    %{workspace: workspace, agent: agent}
  end

  defp memories_path(ws, agent) do
    ~p"/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/agents/#{agent.id}/memories"
  end

  describe "Index" do
    test "shows empty state", %{conn: conn, workspace: ws, agent: agent} do
      {:ok, _view, html} = live(conn, memories_path(ws, agent))

      assert html =~ "Memories"
      assert html =~ "No memories yet"
    end

    test "lists memories", %{conn: conn, workspace: ws, agent: agent} do
      agent_memory_fixture(agent.id, ws.id, %{
        content: "User prefers dark mode",
        type: :preference
      })

      agent_memory_fixture(agent.id, ws.id, %{content: "API endpoint is /v2", type: :fact})

      {:ok, _view, html} = live(conn, memories_path(ws, agent))

      assert html =~ "User prefers dark mode"
      assert html =~ "API endpoint is /v2"
      assert html =~ "preference"
      assert html =~ "fact"
    end

    test "filters by type", %{conn: conn, workspace: ws, agent: agent} do
      agent_memory_fixture(agent.id, ws.id, %{content: "A fact", type: :fact})
      agent_memory_fixture(agent.id, ws.id, %{content: "A preference", type: :preference})

      {:ok, view, _html} = live(conn, memories_path(ws, agent))

      html = render_change(view, "filter_type", %{"type" => "fact"})

      assert html =~ "A fact"
      refute html =~ "A preference"
    end

    test "clears type filter", %{conn: conn, workspace: ws, agent: agent} do
      agent_memory_fixture(agent.id, ws.id, %{content: "A fact", type: :fact})
      agent_memory_fixture(agent.id, ws.id, %{content: "A preference", type: :preference})

      {:ok, view, _html} = live(conn, memories_path(ws, agent))

      render_change(view, "filter_type", %{"type" => "fact"})
      html = render_change(view, "filter_type", %{"type" => ""})

      assert html =~ "A fact"
      assert html =~ "A preference"
    end

    test "deletes a memory", %{conn: conn, workspace: ws, agent: agent} do
      memory = agent_memory_fixture(agent.id, ws.id, %{content: "To delete"})

      {:ok, view, _html} = live(conn, memories_path(ws, agent))

      render_click(view, "delete", %{"id" => memory.id})

      html = render(view)
      refute html =~ "To delete"
    end

    test "bulk prunes low confidence memories", %{conn: conn, workspace: ws, agent: agent} do
      agent_memory_fixture(agent.id, ws.id, %{content: "Strong", confidence: 0.9})
      agent_memory_fixture(agent.id, ws.id, %{content: "Weak", confidence: 0.1})

      {:ok, view, _html} = live(conn, memories_path(ws, agent))

      render_click(view, "bulk_delete_below", %{"threshold" => "0.3"})

      html = render(view)
      assert html =~ "Strong"
      refute html =~ "Weak"
    end
  end

  describe "Edit" do
    test "opens edit modal and saves", %{conn: conn, workspace: ws, agent: agent} do
      memory = agent_memory_fixture(agent.id, ws.id, %{content: "Original content"})

      {:ok, view, _html} = live(conn, memories_path(ws, agent))

      render_click(view, "edit", %{"id" => memory.id})
      html = render(view)
      assert html =~ "Edit Memory"
      assert html =~ "Original content"

      render_submit(view, "save_edit", %{
        "agent_memory" => %{"content" => "Updated content", "confidence" => "0.8"}
      })

      html = render(view)
      assert html =~ "Updated content"
    end

    test "cancels edit", %{conn: conn, workspace: ws, agent: agent} do
      memory = agent_memory_fixture(agent.id, ws.id, %{content: "Some content"})

      {:ok, view, _html} = live(conn, memories_path(ws, agent))

      render_click(view, "edit", %{"id" => memory.id})
      assert render(view) =~ "Edit Memory"

      render_click(view, "cancel_edit")
      refute render(view) =~ "Edit Memory"
    end
  end
end
