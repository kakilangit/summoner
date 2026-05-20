defmodule Summoner.Services.Inference.DiscoveryTest do
  use Summoner.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Summoner.Domain.Schemas.Provider
  alias Summoner.Services.Inference.Discovery

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup do
    # Discovery spawns tasks that need DB access
    Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp create_provider(_context) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    %{scope: scope, workspace: workspace}
  end

  describe "probe_all/1" do
    setup :create_provider

    test "updates provider status to online on success", %{scope: scope, workspace: workspace} do
      # Start a TCP listener to simulate an online provider
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listener)

      provider =
        provider_fixture(scope, workspace.id, %{
          kind: "ollama",
          api_format: :openai,
          base_url: "http://localhost:#{port}"
        })

      name = :"discovery_#{System.unique_integer([:positive])}"
      {:ok, _pid} = Discovery.start_link(name: name, interval: :timer.hours(1))

      poll_until(fn ->
        Repo.get!(Provider, provider.id).status == :online
      end)

      updated = Repo.get!(Provider, provider.id)
      assert updated.status == :online

      :gen_tcp.close(listener)
    end

    test "updates provider status to offline on failure", %{scope: scope, workspace: workspace} do
      provider =
        provider_fixture(scope, workspace.id, %{
          kind: "ollama",
          api_format: :openai,
          base_url: "http://localhost:1"
        })

      name = :"discovery_#{System.unique_integer([:positive])}"
      {:ok, _pid} = Discovery.start_link(name: name, interval: :timer.hours(1))

      poll_until(fn ->
        Repo.get!(Provider, provider.id).status == :offline
      end)

      updated = Repo.get!(Provider, provider.id)
      assert updated.status == :offline
    end

    test "cloud providers are always online", %{scope: scope, workspace: workspace} do
      cloud_provider =
        provider_fixture(scope, workspace.id, %{
          kind: "openai",
          api_format: :openai,
          type: :cloud,
          base_url: "https://api.openai.com",
          name: "openai-cloud"
        })

      name = :"discovery_#{System.unique_integer([:positive])}"
      {:ok, _pid} = Discovery.start_link(name: name, interval: :timer.hours(1))

      poll_until(fn ->
        Repo.get!(Provider, cloud_provider.id).status == :online
      end)

      cloud = Repo.get!(Provider, cloud_provider.id)
      assert cloud.status == :online
    end
  end

  defp poll_until(fun, timeout \\ 2_000, interval \\ 50) do
    deadline = System.monotonic_time(:millisecond) + timeout

    poll_loop(fun, deadline, interval)
  end

  defp poll_loop(fun, deadline, interval) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk("poll_until timed out")
      else
        Process.sleep(interval)
        poll_loop(fun, deadline, interval)
      end
    end
  end
end
