defmodule Summoner.HarnessTest do
  use ExUnit.Case, async: true

  alias Summoner.Harness

  # -------------------------------------------------------------------
  # run/2
  # -------------------------------------------------------------------

  describe "run/2" do
    test "empty list returns {:ok, []}" do
      assert {:ok, []} = Harness.run([])
    end

    test "single unit runs inline" do
      assert {:ok, [{:ok, :a, 42}]} = Harness.run([{:a, fn -> 42 end}])
    end

    test "multiple units return results in order" do
      units = [
        {:a,
         fn ->
           :timer.sleep(50)
           1
         end},
        {:b, fn -> 2 end},
        {:c, fn -> 3 end}
      ]

      assert {:ok, results} = Harness.run(units)
      assert Enum.map(results, fn {:ok, k, _} -> k end) == [:a, :b, :c]
      assert Enum.map(results, fn {:ok, _, v} -> v end) == [1, 2, 3]
    end

    test "respects max_concurrency" do
      counter = :counters.new(1, [:atomics])

      units =
        for i <- 1..10 do
          {i,
           fn ->
             :counters.add(counter, 1, 1)
             current = :counters.get(counter, 1)
             :timer.sleep(20)
             :counters.sub(counter, 1, 1)
             current
           end}
        end

      assert {:ok, results} = Harness.run(units, max_concurrency: 2)
      max_seen = results |> Enum.map(fn {:ok, _, v} -> v end) |> Enum.max()
      assert max_seen <= 2
    end

    test "per-unit timeout kills slow units" do
      units = [
        {:fast, fn -> :done end},
        {:slow,
         fn ->
           :timer.sleep(5_000)
           :never
         end}
      ]

      assert {:partial, [{:ok, :fast, :done}], [{:error, :slow, :timeout}]} =
               Harness.run(units, timeout: 100)
    end

    test "best_effort returns partial on mixed results" do
      units = [
        {:ok_unit, fn -> :good end},
        {:bad_unit, fn -> raise "boom" end}
      ]

      assert {:partial, [{:ok, :ok_unit, :good}], [{:error, :bad_unit, %RuntimeError{}}]} =
               Harness.run(units)
    end

    test "fail_fast returns error on first failure and cancels remaining" do
      units = [
        {:fail, fn -> raise "fail" end},
        {:slow,
         fn ->
           :timer.sleep(5_000)
           :never
         end}
      ]

      assert {:error, :fail, %RuntimeError{message: "fail"}} =
               Harness.run(units, failure_policy: :fail_fast, timeout: 5_000)
    end

    test "on_start and on_complete callbacks invoked" do
      test_pid = self()

      units = [{:x, fn -> 42 end}]

      Harness.run(units,
        on_start: fn key -> send(test_pid, {:started, key}) end,
        on_complete: fn key, result -> send(test_pid, {:completed, key, result}) end
      )

      assert_receive {:started, :x}
      assert_receive {:completed, :x, {:ok, 42}}
    end
  end

  # -------------------------------------------------------------------
  # run_grouped/2
  # -------------------------------------------------------------------

  describe "run_grouped/2" do
    test "empty list returns {:ok, []}" do
      assert {:ok, []} = Harness.run_grouped([])
    end

    test "serializes within group, parallelizes across groups" do
      test_pid = self()

      units = [
        {:group_a,
         {:a1,
          fn ->
            send(test_pid, {:a1, System.monotonic_time()})
            :timer.sleep(30)
            :a1
          end}},
        {:group_a,
         {:a2,
          fn ->
            send(test_pid, {:a2, System.monotonic_time()})
            :a2
          end}},
        {:group_b,
         {:b1,
          fn ->
            send(test_pid, {:b1, System.monotonic_time()})
            :timer.sleep(30)
            :b1
          end}}
      ]

      assert {:ok, results} = Harness.run_grouped(units, max_concurrency: 4)

      # a1 and a2 are in same group — a2 should start after a1
      assert_receive {:a1, t_a1}
      assert_receive {:a2, t_a2}
      assert_receive {:b1, t_b1}

      # a2 starts after a1 (sequential within group)
      assert t_a2 > t_a1
      # b1 starts around the same time as a1 (parallel across groups)
      # Allow some scheduling slack
      assert abs(t_b1 - t_a1) < System.convert_time_unit(50, :millisecond, :native)

      # Results in original order
      keys = Enum.map(results, fn {:ok, k, _} -> k end)
      assert keys == [:a1, :a2, :b1]
    end
  end

  # -------------------------------------------------------------------
  # stream/2
  # -------------------------------------------------------------------

  describe "stream/2" do
    test "empty list returns empty stream" do
      assert [] == Harness.stream([]) |> Enum.to_list()
    end

    test "yields results as they complete" do
      units = [
        {:slow,
         fn ->
           :timer.sleep(50)
           :slow_result
         end},
        {:fast, fn -> :fast_result end}
      ]

      results = Harness.stream(units) |> Enum.to_list()
      assert length(results) == 2

      keys = Enum.map(results, fn {_, k, _} -> k end)
      assert :fast in keys
      assert :slow in keys
    end

    test "fast unit arrives before slow unit" do
      units = [
        {:slow,
         fn ->
           :timer.sleep(100)
           :slow
         end},
        {:fast, fn -> :fast end}
      ]

      [first | _] = Harness.stream(units) |> Enum.to_list()
      assert {:ok, :fast, :fast} = first
    end
  end

  # -------------------------------------------------------------------
  # Telemetry
  # -------------------------------------------------------------------

  describe "telemetry" do
    test "emits start, unit_start, unit_stop, and stop events" do
      test_pid = self()

      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end

      events = [
        [:summoner, :harness, :start],
        [:summoner, :harness, :unit_start],
        [:summoner, :harness, :unit_stop],
        [:summoner, :harness, :stop]
      ]

      handler_id = "harness-test-#{System.unique_integer()}"

      :telemetry.attach_many(handler_id, events, handler, nil)

      Harness.run([{:t, fn -> :ok end}], surface: :test)

      assert_receive {:telemetry, [:summoner, :harness, :start], _, %{surface: :test}}
      assert_receive {:telemetry, [:summoner, :harness, :unit_start], _, %{key: :t}}
      assert_receive {:telemetry, [:summoner, :harness, :unit_stop], _, %{key: :t}}
      assert_receive {:telemetry, [:summoner, :harness, :stop], _, %{surface: :test}}

      :telemetry.detach(handler_id)
    end

    test "emits unit_exception on failure" do
      test_pid = self()

      handler = fn event, _measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, metadata})
      end

      :telemetry.attach(
        "harness-exc-test-#{System.unique_integer()}",
        [:summoner, :harness, :unit_exception],
        handler,
        nil
      )

      Harness.run([{:bad, fn -> raise "boom" end}])

      assert_receive {:telemetry, [:summoner, :harness, :unit_exception], %{key: :bad}}
    end
  end

  # -------------------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------------------

  describe "edge cases" do
    test "caller process exit propagates to tasks" do
      test_pid = self()

      caller =
        spawn(fn ->
          Harness.run([{:long, fn -> :timer.sleep(60_000) end}], timeout: 60_000)
          send(test_pid, :should_not_reach)
        end)

      :timer.sleep(50)
      Process.exit(caller, :kill)
      :timer.sleep(100)

      refute_receive :should_not_reach
    end
  end
end
