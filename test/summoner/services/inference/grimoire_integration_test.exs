defmodule Summoner.Services.Inference.GrimoireIntegrationTest do
  @moduledoc """
  Integration test for the full grimoire provider flow.

  Starts a mock HTTP server (Bandit + Plug) that simulates a grimoire
  plugin container, then exercises list_models and chat through the
  Summoner inference gateway.
  """
  use Summoner.DataCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.PluginsFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  alias Summoner.Domain.Schemas.Provider
  alias Summoner.Ports.Persistence.Providers
  alias Summoner.Services.Inference

  # -------------------------------------------------------------------
  # Mock grimoire server
  # -------------------------------------------------------------------

  defmodule MockGrimoire do
    @moduledoc false
    use Plug.Router

    plug :match
    plug Plug.Parsers, parsers: [:json], json_decoder: Jason
    plug :dispatch

    get "/models" do
      body = %{
        models: [
          %{id: "mock-7b", name: "Mock 7B", context_length: 8192, capabilities: ["chat"]},
          %{
            id: "mock-13b",
            name: "Mock 13B",
            context_length: 16_384,
            capabilities: ["chat", "tools"]
          }
        ]
      }

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(body))
    end

    post "/chat" do
      %{"messages" => messages, "model" => model} = conn.body_params

      last_message = List.last(messages)
      reply = "Hello from #{model}! You said: #{last_message["content"]}"

      body = %{
        message: %{role: "assistant", content: reply},
        usage: %{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30},
        finish_reason: "stop"
      }

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(body))
    end

    match _ do
      send_resp(conn, 404, "not found")
    end
  end

  # -------------------------------------------------------------------
  # Setup
  # -------------------------------------------------------------------

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)

    # Use real HTTP client for this integration test
    original_client = Application.get_env(:arcanum, :http_client)
    Application.put_env(:arcanum, :http_client, Req)

    # Start mock grimoire server on a random port
    {:ok, server} = Bandit.start_link(plug: MockGrimoire, port: 0, ip: :loopback)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    # Create a grimoire provider pointing to our mock server
    plugin =
      plugin_fixture(workspace.id, %{
        capabilities: ["provider"],
        manifest: valid_manifest(%{"capabilities" => ["provider"]})
      })

    {:ok, provider} =
      Providers.create_grimoire_provider(%{
        name: "grimoire:mock-provider",
        workspace_id: workspace.id,
        plugin_installation_id: plugin.id
      })

    # Manually set base_url to mock server (bypassing container resolution)
    provider =
      provider
      |> Ecto.Changeset.change(%{base_url: "http://127.0.0.1:#{port}"})
      |> Summoner.Repo.update!()
      |> Map.put(:plugin_installation, plugin)

    on_exit(fn ->
      try do
        ThousandIsland.stop(server)
      catch
        :exit, _ -> :ok
      end

      Application.put_env(:arcanum, :http_client, original_client)
    end)

    %{provider: provider, workspace: workspace, port: port}
  end

  # -------------------------------------------------------------------
  # Tests
  # -------------------------------------------------------------------

  describe "list_models through grimoire provider" do
    test "returns model IDs from the mock server", %{provider: provider} do
      assert {:ok, models} = Inference.Gateway.list_models(provider)
      assert "mock-7b" in models
      assert "mock-13b" in models
      assert length(models) == 2
    end
  end

  describe "chat through grimoire provider" do
    test "returns a response from the mock server", %{provider: provider} do
      intent = %Arcanum.Intent{
        model: "mock-7b",
        messages: [
          %{role: :user, content: [%{type: :text, text: "Hello!"}]}
        ]
      }

      assert {:ok, response} = Inference.Gateway.chat(provider, intent)
      assert %Arcanum.Response{} = response
      text = Arcanum.Response.text(response)
      assert text =~ "Hello from mock-7b"
      assert text =~ "Hello!"
      assert response.finish_reason == "stop"
      assert response.usage.prompt_tokens == 10
      assert response.usage.completion_tokens == 20
    end

    test "passes tools in the request", %{provider: provider} do
      intent = %Arcanum.Intent{
        model: "mock-13b",
        messages: [
          %{role: :user, content: [%{type: :text, text: "Use a tool"}]}
        ],
        tools: [
          %{
            type: "function",
            function: %{
              name: "search",
              description: "Search the web",
              parameters: %{type: "object", properties: %{}}
            }
          }
        ]
      }

      assert {:ok, response} = Inference.Gateway.chat(provider, intent)
      assert Arcanum.Response.text(response) =~ "mock-13b"
    end
  end

  describe "error handling" do
    test "returns error when container not available" do
      # Provider with nil base_url and no container
      provider = %Provider{
        id: Nulid.generate(),
        name: "grimoire:broken",
        kind: "grimoire",
        api_format: :grimoire,
        type: :local,
        base_url: nil,
        status: :online,
        plugin_installation: nil
      }

      assert {:error, :container_not_available} = Inference.Gateway.list_models(provider)
    end
  end
end
