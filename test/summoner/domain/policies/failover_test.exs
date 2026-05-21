defmodule Summoner.Domain.Policies.FailoverTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Policies.Failover
  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.AgentFailoverEntry

  describe "handle_failure/3" do
    test "returns :not_eligible for non-failover errors" do
      agent = build_agent(chain: [entry("backup-1", 0)])

      assert :not_eligible == Failover.handle_failure(agent, :unknown_error, 0)
      assert :not_eligible == Failover.handle_failure(agent, {:validation, "bad input"}, 0)
    end

    test "returns :no_backup when agent has empty failover chain" do
      agent = build_agent(chain: [])

      assert :no_backup == Failover.handle_failure(agent, {:api_error, 500, "error"}, 0)
    end

    test "returns {:failover, :auto} for eligible errors with auto strategy" do
      agent = build_agent(chain: [entry("backup-1", 0)], failover_strategy: :auto)

      assert {:failover, :auto} ==
               Failover.handle_failure(agent, {:api_error, 500, "error"}, 0)
    end

    test "returns :failover_pending for manual strategy" do
      agent = build_agent(chain: [entry("backup-1", 0)], failover_strategy: :manual)

      assert :failover_pending ==
               Failover.handle_failure(agent, {:api_error, 429, "rate limited"}, 0)
    end

    test "returns {:failover_delayed, delay_ms} for notify_then_auto strategy" do
      agent =
        build_agent(
          chain: [entry("backup-1", 0)],
          failover_strategy: :notify_then_auto,
          failover_delay_ms: 5000
        )

      assert {:failover_delayed, 5000} ==
               Failover.handle_failure(agent, {:timeout, :connection}, 0)
    end

    test "returns :max_depth_reached when depth exceeds max" do
      agent = build_agent(chain: [entry("backup-1", 0)], max_failover_depth: 3)

      assert :max_depth_reached == Failover.handle_failure(agent, {:api_error, 500, "error"}, 3)
      assert :max_depth_reached == Failover.handle_failure(agent, {:api_error, 500, "error"}, 5)
    end

    test "allows failover when depth is below max" do
      agent = build_agent(chain: [entry("backup-1", 0)], max_failover_depth: 3)

      assert {:failover, :auto} ==
               Failover.handle_failure(agent, {:api_error, 500, "error"}, 2)
    end

    test "handles multiple entries in chain (policy just checks non-empty)" do
      agent =
        build_agent(chain: [entry("backup-1", 0), entry("backup-2", 1), entry("backup-3", 2)])

      assert {:failover, :auto} ==
               Failover.handle_failure(agent, {:api_error, 529, "overloaded"}, 0)
    end
  end

  describe "failover_eligible?/1" do
    test "eligible for HTTP 429, 500, 502, 503, 529" do
      for status <- [429, 500, 502, 503, 529] do
        assert Failover.failover_eligible?({:api_error, status, "body"})
      end
    end

    test "not eligible for HTTP 400, 401, 403, 404" do
      for status <- [400, 401, 403, 404] do
        refute Failover.failover_eligible?({:api_error, status, "body"})
      end
    end

    test "eligible for timeout, connection_error, a2a_error" do
      assert Failover.failover_eligible?({:timeout, :connect})
      assert Failover.failover_eligible?({:connection_error, :nxdomain})
      assert Failover.failover_eligible?({:a2a_error, "unavailable"})
      assert Failover.failover_eligible?({:model_not_found, "gpt-5"})
      assert Failover.failover_eligible?({:budget_exhausted, "over limit"})
    end

    test "not eligible for unknown errors" do
      refute Failover.failover_eligible?(:unknown)
      refute Failover.failover_eligible?({:validation, "bad"})
    end
  end

  describe "creates_cycle?/3" do
    test "self-backup is a cycle" do
      assert Failover.creates_cycle?("a", "a", fn _ -> [] end)
    end

    test "detects simple A↔B cycle" do
      # A's chain has B, now we want to add A to B's chain
      get_chain = fn
        "a" -> [%{backup_agent_id: "b"}]
        "b" -> []
        _ -> []
      end

      # Adding A as backup of B: check if B→A creates cycle
      # B's proposed chain would include A, and A's chain includes B → cycle
      assert Failover.creates_cycle?("b", "a", get_chain)
    end

    test "detects longer A→B→C→A cycle" do
      get_chain = fn
        "b" -> [%{backup_agent_id: "c"}]
        "c" -> [%{backup_agent_id: "a"}]
        _ -> []
      end

      # Adding B as backup of A: A→B→C→A would be a cycle
      assert Failover.creates_cycle?("a", "b", get_chain)
    end

    test "no cycle for linear chain" do
      get_chain = fn
        "b" -> [%{backup_agent_id: "c"}]
        "c" -> []
        _ -> []
      end

      refute Failover.creates_cycle?("a", "b", get_chain)
    end

    test "no cycle when backup has no further backups" do
      get_chain = fn _ -> [] end

      refute Failover.creates_cycle?("a", "b", get_chain)
    end

    test "handles multi-entry chains in cycle check" do
      get_chain = fn
        "b" -> [%{backup_agent_id: "c"}, %{backup_agent_id: "d"}]
        "d" -> [%{backup_agent_id: "a"}]
        _ -> []
      end

      # A→B, B has [C, D], D→A — cycle through D
      assert Failover.creates_cycle?("a", "b", get_chain)
    end
  end

  # --- Helpers ---

  defp build_agent(opts) do
    %Agent{
      id: Keyword.get(opts, :id, "agent-id"),
      failover_chain: Keyword.get(opts, :chain, []),
      failover_strategy: Keyword.get(opts, :failover_strategy, :auto),
      failover_delay_ms: Keyword.get(opts, :failover_delay_ms, 0),
      max_failover_depth: Keyword.get(opts, :max_failover_depth, 3)
    }
  end

  defp entry(backup_agent_id, position) do
    %AgentFailoverEntry{
      backup_agent_id: backup_agent_id,
      position: position
    }
  end
end
