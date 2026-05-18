defmodule Summoner.Inference.ProbeTest do
  use ExUnit.Case, async: true

  alias Arcanum.Probe

  describe "probe_provider/1" do
    test "returns :online for cloud providers without probing" do
      assert Probe.probe_provider(%{type: :cloud}) == :online
    end

    test "returns :online when TCP connect succeeds" do
      # Start a TCP listener to simulate an online provider
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listener)

      provider = %{type: :local, base_url: "http://localhost:#{port}"}
      assert Probe.probe_provider(provider) == :online

      :gen_tcp.close(listener)
    end

    test "returns :offline when TCP connect fails" do
      # Use a port that nothing is listening on
      provider = %{type: :local, base_url: "http://localhost:1"}
      assert Probe.probe_provider(provider) == :offline
    end

    test "returns :offline for invalid base_url" do
      provider = %{type: :local, base_url: "not-a-url"}
      assert Probe.probe_provider(provider) == :offline
    end

    test "returns :offline for nil base_url" do
      provider = %{type: :local, base_url: nil}
      assert Probe.probe_provider(provider) == :offline
    end

    test "parses port from URL correctly" do
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listener)

      # With /v1 path suffix
      provider = %{type: :local, base_url: "http://localhost:#{port}/v1"}
      assert Probe.probe_provider(provider) == :online

      :gen_tcp.close(listener)
    end
  end
end
