defmodule Summoner.Ports.Harness do
  @moduledoc """
  Stateless parallel execution module.

  Provides a unified interface for running units of work concurrently with
  configurable concurrency limits, timeouts, failure policies, and telemetry.

  All functions accept a list of `{key, fun}` tuples where `key` is an opaque
  identifier and `fun` is a zero-arity function to execute.

  ## Options

  - `:max_concurrency` — maximum concurrent tasks, default `System.schedulers_online()`
  - `:timeout` — per-unit timeout in ms, default `300_000` (5 minutes)
  - `:failure_policy` — `:best_effort` (default) or `:fail_fast`
  - `:on_start` — `fn key -> :ok`, called when a unit begins
  - `:on_complete` — `fn key, result -> :ok`, called when a unit finishes
  - `:task_supervisor` — supervisor for spawned tasks, default `Summoner.TaskSupervisor`
  - `:surface` — atom identifying the calling subsystem for telemetry metadata
  """

  require Logger

  @default_timeout :timer.minutes(5)
  @default_max_concurrency System.schedulers_online()

  @type key :: term()
  @type unit :: {key(), (-> term())}
  @type result :: {:ok, key(), term()} | {:error, key(), term()}
  @type run_result :: {:ok, [result()]} | {:partial, [result()], [result()]}

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc """
  Runs all units concurrently, returning results in the original order.

  With `:best_effort` (default), all units run to completion. Returns
  `{:ok, results}` when all succeed, or `{:partial, successes, failures}`
  when some fail.

  With `:fail_fast`, returns `{:error, key, reason}` on the first failure
  and cancels remaining tasks.
  """
  @spec run([unit()], keyword()) :: run_result() | {:error, key(), term()}
  def run(units, opts \\ [])

  def run([], _opts), do: {:ok, []}

  def run([{key, fun}], opts) do
    emit_start(opts)
    result = execute_single(key, fun, opts)
    emit_stop(opts, [result])
    wrap_results([result])
  end

  def run(units, opts) do
    opts = normalize_opts(opts)
    emit_start(opts)

    results =
      case Keyword.get(opts, :failure_policy, :best_effort) do
        :best_effort -> run_best_effort(units, opts)
        :fail_fast -> run_fail_fast(units, opts)
      end

    emit_stop(opts, results)
    results
  end

  @doc """
  Runs units grouped by a key. Units within the same group run sequentially;
  groups run in parallel.

  Each unit is a `{group_key, {unit_key, fun}}` tuple.
  """
  @spec run_grouped([{term(), unit()}], keyword()) :: run_result() | {:error, key(), term()}
  def run_grouped(units, opts \\ [])

  def run_grouped([], _opts), do: {:ok, []}

  def run_grouped(units, opts) do
    opts = normalize_opts(opts)
    order = build_unit_order(units)
    groups = build_groups(units, opts)

    emit_start(opts)

    flat_results = execute_groups(groups, opts)
    final = finalize_grouped(flat_results, order)

    emit_stop(opts, final)
    final
  end

  @doc """
  Runs units concurrently, returning a stream that yields results as they
  complete. Order is not guaranteed.
  """
  @spec stream([unit()], keyword()) :: Enumerable.t()
  def stream(units, opts \\ [])

  def stream([], _opts), do: Stream.map([], & &1)

  def stream(units, opts) do
    opts = normalize_opts(opts)
    supervisor = Keyword.get(opts, :task_supervisor)
    timeout = Keyword.get(opts, :timeout)

    emit_start(opts)

    tasks =
      Enum.map(units, fn {key, fun} ->
        task =
          Task.Supervisor.async_nolink(supervisor, fn ->
            {key, fun.()}
          end)

        {task.ref, key}
      end)

    ref_to_key = Map.new(tasks)

    Stream.resource(
      fn -> ref_to_key end,
      fn
        refs when map_size(refs) == 0 ->
          {:halt, :done}

        refs ->
          receive do
            {ref, {key, value}} when is_map_key(refs, ref) ->
              Process.demonitor(ref, [:flush])
              invoke_callback(opts, :on_complete, [key, {:ok, value}])
              {[{:ok, key, value}], Map.delete(refs, ref)}

            {:DOWN, ref, :process, _pid, reason} when is_map_key(refs, ref) ->
              key = Map.get(refs, ref)
              invoke_callback(opts, :on_complete, [key, {:error, reason}])
              {[{:error, key, reason}], Map.delete(refs, ref)}
          after
            timeout ->
              remaining_results =
                Enum.map(refs, fn {_ref, key} ->
                  {:error, key, :timeout}
                end)

              {remaining_results, %{}}
          end
      end,
      fn _ -> :ok end
    )
  end

  # -------------------------------------------------------------------
  # Private — run_grouped helpers
  # -------------------------------------------------------------------

  defp build_unit_order(units) do
    units
    |> Enum.with_index()
    |> Map.new(fn {{_group, {unit_key, _fun}}, idx} -> {unit_key, idx} end)
  end

  defp build_groups(units, opts) do
    units
    |> Enum.group_by(fn {group_key, _} -> group_key end, fn {_, unit} -> unit end)
    |> Enum.map(fn {group_key, group_units} ->
      {group_key, fn -> run_group_sequentially(group_units, opts) end}
    end)
  end

  defp run_group_sequentially(group_units, opts) do
    Enum.map(group_units, fn {unit_key, fun} -> execute_single(unit_key, fun, opts) end)
  end

  defp execute_groups(groups, opts) do
    case Keyword.get(opts, :failure_policy, :best_effort) do
      :best_effort -> flatten_best_effort(run_best_effort(groups, opts))
      :fail_fast -> flatten_fail_fast(run_fail_fast(groups, opts))
    end
  end

  defp flatten_best_effort({:ok, group_results}) do
    Enum.flat_map(group_results, fn {:ok, _gk, inner} -> inner end)
  end

  defp flatten_best_effort({:partial, successes, failures}) do
    ok_flat = Enum.flat_map(successes, fn {:ok, _gk, inner} -> inner end)
    err_flat = Enum.flat_map(failures, fn {:error, _gk, reason} -> [{:error, reason}] end)
    {:mixed, ok_flat, err_flat}
  end

  defp flatten_fail_fast({:error, _group_key, reason}), do: {:fail, reason}

  defp flatten_fail_fast({:ok, group_results}) do
    Enum.flat_map(group_results, fn {:ok, _gk, inner} -> inner end)
  end

  defp finalize_grouped({:fail, reason}, _order), do: {:error, :group, reason}

  defp finalize_grouped({:mixed, oks, errs}, order) do
    sorted = Enum.sort_by(oks, fn {_, key, _} -> Map.get(order, key, 0) end)
    {:partial, sorted, errs}
  end

  defp finalize_grouped(results, order) when is_list(results) do
    sorted = Enum.sort_by(results, fn {_, key, _} -> Map.get(order, key, 0) end)
    wrap_results(sorted)
  end

  # -------------------------------------------------------------------
  # Private — execution strategies
  # -------------------------------------------------------------------

  defp run_best_effort(units, opts) do
    max = Keyword.get(opts, :max_concurrency)
    timeout = Keyword.get(opts, :timeout)
    supervisor = Keyword.get(opts, :task_supervisor)

    results =
      supervisor
      |> Task.Supervisor.async_stream_nolink(
        units,
        fn {key, fun} ->
          invoke_callback(opts, :on_start, [key])
          emit_unit_start(opts, key)

          try do
            value = fun.()
            emit_unit_stop(opts, key)
            invoke_callback(opts, :on_complete, [key, {:ok, value}])
            {:ok, key, value}
          rescue
            e ->
              emit_unit_exception(opts, key, e)
              invoke_callback(opts, :on_complete, [key, {:error, e}])
              {:error, key, e}
          end
        end,
        max_concurrency: max,
        timeout: timeout,
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.with_index()
      |> Enum.map(fn
        {{:ok, result}, _idx} ->
          result

        {{:exit, :timeout}, idx} ->
          {key, _fun} = Enum.at(units, idx)
          emit_unit_exception(opts, key, :timeout)
          invoke_callback(opts, :on_complete, [key, {:error, :timeout}])
          {:error, key, :timeout}
      end)

    wrap_results(results)
  end

  defp run_fail_fast(units, opts) do
    supervisor = Keyword.get(opts, :task_supervisor)
    timeout = Keyword.get(opts, :timeout)

    tasks =
      Enum.map(units, fn {key, fun} ->
        task =
          Task.Supervisor.async_nolink(supervisor, fn ->
            invoke_callback(opts, :on_start, [key])
            emit_unit_start(opts, key)

            try do
              value = fun.()
              emit_unit_stop(opts, key)
              invoke_callback(opts, :on_complete, [key, {:ok, value}])
              {:ok, key, value}
            rescue
              e ->
                emit_unit_exception(opts, key, e)
                invoke_callback(opts, :on_complete, [key, {:error, e}])
                {:error, key, e}
            end
          end)

        {task, key}
      end)

    deadline = System.monotonic_time(:millisecond) + timeout
    collect_fail_fast(tasks, [], deadline, opts)
  end

  defp collect_fail_fast([], acc, _deadline, _opts), do: wrap_results(Enum.reverse(acc))

  defp collect_fail_fast(tasks, acc, deadline, opts) do
    remaining_ms = max(deadline - System.monotonic_time(:millisecond), 0)

    ref_to_key = Map.new(tasks, fn {task, key} -> {task.ref, key} end)

    receive do
      {ref, {:ok, _key, _value} = result} when is_map_key(ref_to_key, ref) ->
        Process.demonitor(ref, [:flush])
        remaining = Enum.reject(tasks, fn {t, _} -> t.ref == ref end)
        collect_fail_fast(remaining, [result | acc], deadline, opts)

      {ref, {:error, key, reason}} when is_map_key(ref_to_key, ref) ->
        Process.demonitor(ref, [:flush])
        cancel_remaining(tasks, ref, opts)
        {:error, key, reason}

      {:DOWN, ref, :process, _pid, reason} when is_map_key(ref_to_key, ref) ->
        key = Map.get(ref_to_key, ref)
        Process.demonitor(ref, [:flush])
        cancel_remaining(tasks, ref, opts)
        {:error, key, reason}
    after
      remaining_ms ->
        Enum.each(tasks, fn {task, key} ->
          Task.Supervisor.terminate_child(
            Keyword.get(opts, :task_supervisor),
            task.pid
          )

          emit_unit_exception(opts, key, :timeout)
        end)

        {:error, :batch, :timeout}
    end
  end

  defp cancel_remaining(tasks, completed_ref, opts) do
    Enum.each(tasks, fn {task, _key} ->
      if task.ref != completed_ref do
        Process.demonitor(task.ref, [:flush])

        Task.Supervisor.terminate_child(
          Keyword.get(opts, :task_supervisor),
          task.pid
        )
      end
    end)
  end

  # -------------------------------------------------------------------
  # Private — single unit execution
  # -------------------------------------------------------------------

  defp execute_single(key, fun, opts) do
    invoke_callback(opts, :on_start, [key])
    emit_unit_start(opts, key)

    try do
      value = fun.()
      emit_unit_stop(opts, key)
      invoke_callback(opts, :on_complete, [key, {:ok, value}])
      {:ok, key, value}
    rescue
      e ->
        emit_unit_exception(opts, key, e)
        invoke_callback(opts, :on_complete, [key, {:error, e}])
        {:error, key, e}
    end
  end

  # -------------------------------------------------------------------
  # Private — result wrapping
  # -------------------------------------------------------------------

  defp wrap_results(results) do
    {oks, errs} = Enum.split_with(results, fn {tag, _, _} -> tag == :ok end)

    case errs do
      [] -> {:ok, oks}
      _ -> {:partial, oks, errs}
    end
  end

  # -------------------------------------------------------------------
  # Private — callbacks
  # -------------------------------------------------------------------

  defp invoke_callback(opts, name, args) do
    case Keyword.get(opts, name) do
      fun when is_function(fun) -> apply(fun, args)
      nil -> :ok
    end
  end

  # -------------------------------------------------------------------
  # Private — telemetry
  # -------------------------------------------------------------------

  defp emit_start(opts) do
    :telemetry.execute(
      [:summoner, :harness, :start],
      %{system_time: System.system_time()},
      %{surface: Keyword.get(opts, :surface, :unknown)}
    )
  end

  defp emit_stop(opts, results) do
    count =
      case results do
        {:ok, list} -> length(list)
        {:partial, oks, errs} -> length(oks) + length(errs)
        {:error, _, _} -> 1
        list when is_list(list) -> length(list)
        _ -> 0
      end

    :telemetry.execute(
      [:summoner, :harness, :stop],
      %{system_time: System.system_time(), count: count},
      %{surface: Keyword.get(opts, :surface, :unknown)}
    )
  end

  defp emit_unit_start(opts, key) do
    :telemetry.execute(
      [:summoner, :harness, :unit_start],
      %{system_time: System.system_time()},
      %{surface: Keyword.get(opts, :surface, :unknown), key: key}
    )
  end

  defp emit_unit_stop(opts, key) do
    :telemetry.execute(
      [:summoner, :harness, :unit_stop],
      %{system_time: System.system_time()},
      %{surface: Keyword.get(opts, :surface, :unknown), key: key}
    )
  end

  defp emit_unit_exception(opts, key, reason) do
    :telemetry.execute(
      [:summoner, :harness, :unit_exception],
      %{system_time: System.system_time()},
      %{surface: Keyword.get(opts, :surface, :unknown), key: key, reason: reason}
    )
  end

  # -------------------------------------------------------------------
  # Private — option normalization
  # -------------------------------------------------------------------

  defp normalize_opts(opts) do
    opts
    |> Keyword.put_new(:max_concurrency, @default_max_concurrency)
    |> Keyword.put_new(:timeout, @default_timeout)
    |> Keyword.put_new(:failure_policy, :best_effort)
    |> Keyword.put_new(:task_supervisor, Summoner.TaskSupervisor)
  end
end
