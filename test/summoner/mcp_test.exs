defmodule Summoner.Adapters.Persistence.MCPTest do
  use Summoner.DataCase

  alias Summoner.Adapters.Persistence.MCP

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.MCPFixtures

  defp create_context(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    %{scope: scope, workspace: workspace}
  end

  # -------------------------------------------------------------------
  # MCP Server CRUD
  # -------------------------------------------------------------------

  describe "create_server/2" do
    setup :create_context

    test "creates a stdio server", %{scope: scope, workspace: ws} do
      {:ok, server} =
        MCP.create_server(scope, %{
          name: "my-tool",
          transport: :stdio,
          command_or_url: "/usr/bin/echo",
          workspace_id: ws.id
        })

      assert server.name == "my-tool"
      assert server.transport == :stdio
      assert server.command_or_url == "/usr/bin/echo"
    end

    test "creates an http server", %{scope: scope, workspace: ws} do
      {:ok, server} =
        MCP.create_server(scope, %{
          name: "remote-tool",
          transport: :http,
          command_or_url: "https://mcp.example.com/v1",
          workspace_id: ws.id
        })

      assert server.transport == :http
    end

    test "rejects http server with invalid URL", %{scope: scope, workspace: ws} do
      {:error, changeset} =
        MCP.create_server(scope, %{
          name: "bad-url",
          transport: :http,
          command_or_url: "/usr/bin/not-a-url",
          workspace_id: ws.id
        })

      assert errors_on(changeset).command_or_url
    end

    test "rejects duplicate name in workspace", %{scope: scope, workspace: ws} do
      _server = mcp_server_fixture(scope, ws.id, %{name: "dup"})

      {:error, changeset} =
        MCP.create_server(scope, %{
          name: "dup",
          transport: :stdio,
          command_or_url: "/usr/bin/echo",
          workspace_id: ws.id
        })

      assert errors_on(changeset).workspace_id
    end
  end

  describe "list_servers/2" do
    setup :create_context

    test "lists servers for workspace", %{scope: scope, workspace: ws} do
      _s1 = mcp_server_fixture(scope, ws.id, %{name: "alpha"})
      _s2 = mcp_server_fixture(scope, ws.id, %{name: "beta"})

      servers = MCP.list_servers(scope, ws.id, ws.tenant_id)
      assert length(servers) == 2
      assert Enum.map(servers, & &1.name) == ["alpha", "beta"]
    end

    test "does not list servers from other workspace", %{scope: scope, workspace: ws} do
      other_ws = workspace_fixture(scope, %{name: "other"})
      _s1 = mcp_server_fixture(scope, other_ws.id)

      assert MCP.list_servers(scope, ws.id, ws.tenant_id) == []
    end
  end

  describe "get_server!/3" do
    setup :create_context

    test "gets a server by ID", %{scope: scope, workspace: ws} do
      server = mcp_server_fixture(scope, ws.id)
      fetched = MCP.get_server!(scope, ws.id, ws.tenant_id, server.id)
      assert fetched.id == server.id
    end
  end

  describe "update_server/3" do
    setup :create_context

    test "updates server name", %{scope: scope, workspace: ws} do
      server = mcp_server_fixture(scope, ws.id)
      {:ok, updated} = MCP.update_server(scope, server, %{name: "new-name"})
      assert updated.name == "new-name"
    end
  end

  describe "delete_server/2" do
    setup :create_context

    test "deletes a server", %{scope: scope, workspace: ws} do
      server = mcp_server_fixture(scope, ws.id)
      {:ok, _} = MCP.delete_server(scope, server)
      assert MCP.list_servers(scope, ws.id, ws.tenant_id) == []
    end
  end

  # -------------------------------------------------------------------
  # Equip / Unequip
  # -------------------------------------------------------------------

  describe "equip_server/2 and unequip_server/3" do
    setup :create_context

    setup %{scope: scope, workspace: ws} do
      provider = provider_fixture(scope, ws.id)
      agent = agent_fixture(scope, ws.id, provider.id)
      server = mcp_server_fixture(scope, ws.id)
      %{agent: agent, server: server}
    end

    test "equips server to agent", %{scope: scope, agent: fam, server: srv} do
      {:ok, link} = MCP.equip_server(scope, %{agent_id: fam.id, mcp_server_id: srv.id})
      assert link.agent_id == fam.id
      assert link.mcp_server_id == srv.id
    end

    test "rejects duplicate equip", %{scope: scope, agent: fam, server: srv} do
      {:ok, _} = MCP.equip_server(scope, %{agent_id: fam.id, mcp_server_id: srv.id})

      {:error, changeset} =
        MCP.equip_server(scope, %{agent_id: fam.id, mcp_server_id: srv.id})

      assert errors_on(changeset).agent_id
    end

    test "unequips server from agent", %{scope: scope, agent: fam, server: srv} do
      {:ok, _} = MCP.equip_server(scope, %{agent_id: fam.id, mcp_server_id: srv.id})
      {:ok, _} = MCP.unequip_server(scope, fam.id, srv.id)
      refute MCP.server_equipped?(fam.id, srv.id)
    end

    test "unequip returns error when not equipped", %{scope: scope, agent: fam, server: srv} do
      assert {:error, :not_found} = MCP.unequip_server(scope, fam.id, srv.id)
    end
  end

  describe "list_equipped_servers/1" do
    setup :create_context

    test "lists equipped servers", %{scope: scope, workspace: ws} do
      provider = provider_fixture(scope, ws.id)
      agent = agent_fixture(scope, ws.id, provider.id)
      s1 = mcp_server_fixture(scope, ws.id, %{name: "alpha"})
      s2 = mcp_server_fixture(scope, ws.id, %{name: "beta"})
      _s3 = mcp_server_fixture(scope, ws.id, %{name: "gamma"})

      {:ok, _} = MCP.equip_server(scope, %{agent_id: agent.id, mcp_server_id: s1.id})
      {:ok, _} = MCP.equip_server(scope, %{agent_id: agent.id, mcp_server_id: s2.id})

      equipped = MCP.list_equipped_servers(agent.id)
      assert length(equipped) == 2
      ids = Enum.map(equipped, & &1.id)
      assert s1.id in ids
      assert s2.id in ids
    end

    test "merges per-agent env into server config", %{scope: scope, workspace: ws} do
      provider = provider_fixture(scope, ws.id)
      agent = agent_fixture(scope, ws.id, provider.id)

      server =
        mcp_server_fixture(scope, ws.id, %{
          name: "with-env",
          config: %{"env" => %{"BASE_KEY" => "base_val", "SHARED" => "server_val"}}
        })

      {:ok, _} =
        MCP.equip_server(scope, %{
          agent_id: agent.id,
          mcp_server_id: server.id,
          env: %{"AGENT_KEY" => "agent_val", "SHARED" => "agent_val"}
        })

      [equipped] = MCP.list_equipped_servers(agent.id)
      env = equipped.config["env"]

      # Server env preserved
      assert env["BASE_KEY"] == "base_val"
      # Agent env added
      assert env["AGENT_KEY"] == "agent_val"
      # Agent env wins on conflict
      assert env["SHARED"] == "agent_val"
    end

    test "returns unmodified server when agent env is empty", %{scope: scope, workspace: ws} do
      provider = provider_fixture(scope, ws.id)
      agent = agent_fixture(scope, ws.id, provider.id)

      server =
        mcp_server_fixture(scope, ws.id, %{
          name: "no-agent-env",
          config: %{"env" => %{"KEY" => "val"}}
        })

      {:ok, _} = MCP.equip_server(scope, %{agent_id: agent.id, mcp_server_id: server.id})

      [equipped] = MCP.list_equipped_servers(agent.id)
      assert equipped.config["env"] == %{"KEY" => "val"}
    end
  end

  describe "update_equipped_env/4" do
    setup :create_context

    test "updates per-agent env", %{scope: scope, workspace: ws} do
      provider = provider_fixture(scope, ws.id)
      agent = agent_fixture(scope, ws.id, provider.id)
      server = mcp_server_fixture(scope, ws.id)

      {:ok, _} = MCP.equip_server(scope, %{agent_id: agent.id, mcp_server_id: server.id})

      {:ok, updated} =
        MCP.update_equipped_env(scope, agent.id, server.id, %{"MY_KEY" => "my_val"})

      assert updated.env == %{"MY_KEY" => "my_val"}
    end

    test "returns not_found when not equipped", %{scope: scope, workspace: ws} do
      provider = provider_fixture(scope, ws.id)
      agent = agent_fixture(scope, ws.id, provider.id)
      server = mcp_server_fixture(scope, ws.id)

      assert {:error, :not_found} =
               MCP.update_equipped_env(scope, agent.id, server.id, %{"K" => "V"})
    end
  end

  describe "server_equipped?/2" do
    setup :create_context

    test "returns true when equipped", %{scope: scope, workspace: ws} do
      provider = provider_fixture(scope, ws.id)
      agent = agent_fixture(scope, ws.id, provider.id)
      server = mcp_server_fixture(scope, ws.id)

      {:ok, _} = MCP.equip_server(scope, %{agent_id: agent.id, mcp_server_id: server.id})

      assert MCP.server_equipped?(agent.id, server.id)
    end

    test "returns false when not equipped", %{scope: scope, workspace: ws} do
      provider = provider_fixture(scope, ws.id)
      agent = agent_fixture(scope, ws.id, provider.id)
      server = mcp_server_fixture(scope, ws.id)

      refute MCP.server_equipped?(agent.id, server.id)
    end
  end

  # -------------------------------------------------------------------
  # Allowlist enforcement
  # -------------------------------------------------------------------

  describe "call_tool_for_agent/5" do
    setup :create_context

    test "rejects tool call when server not equipped", %{scope: scope, workspace: ws} do
      provider = provider_fixture(scope, ws.id)
      agent = agent_fixture(scope, ws.id, provider.id)

      server =
        mcp_server_fixture(scope, ws.id, %{
          transport: :http,
          command_or_url: "https://example.com/mcp"
        })

      assert {:error, :not_allowed} =
               MCP.call_tool_for_agent(ws.id, agent.id, server, "some_tool", %{})
    end
  end
end
