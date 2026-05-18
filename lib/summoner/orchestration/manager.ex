defmodule Summoner.Orchestration.Manager do
  @moduledoc """
  Orchestrates manager-worker delegation.

  When a manager agent's ReAct loop produces a subtask plan (via LLM),
  this module validates the plan, persists subtasks, dispatches them
  to workers, evaluates results, and aggregates the final response.

  ## Flow

  1. Manager LLM call returns a JSON subtask plan.
  2. `SubtaskPlan.validate/2` checks worker links and DAG validity.
  3. Subtasks are persisted via `Orchestration.create_subtasks/2`.
  4. Ready subtasks (no unmet deps) are dispatched concurrently via `Dispatcher`.
  5. As subtasks complete, newly-ready subtasks are dispatched.
  6. When all subtasks are terminal, the manager aggregates results.
  """

  require Logger

  alias Summoner.Agents
  alias Summoner.Orchestration
  alias Summoner.Orchestration.{Dispatcher, FailurePolicy, Invocation, SubtaskPlan}
  alias Summoner.Orchestration.Subtask
  alias Summoner.Repo

  @dispatch_retry_backoff_ms 2_000

  @doc """
  Executes a manager delegation plan.

  `plan_json` is the parsed JSON array from the LLM's subtask plan.
  `invocation` is the manager's current invocation.
  `manager_state` is the manager GenServer's current state.

  Returns `{:ok, results}` or `{:error, reason}`.
  """
  def execute_plan(plan_json, invocation, manager_state) do
    agent = manager_state.agent
    linked_workers = load_linked_worker_ids(agent)

    Logger.info(
      "Executing plan with #{length(plan_json)} tasks, #{MapSet.size(linked_workers)} linked workers"
    )

    with {:ok, normalized} <- SubtaskPlan.validate(plan_json, linked_workers),
         {:ok, subtasks} <- persist_subtasks(invocation, normalized) do
      Logger.info("Dispatching #{length(subtasks)} subtasks")
      dispatch_all(subtasks, manager_state)
    else
      {:error, reason} = error ->
        Logger.error("Plan execution failed: #{inspect(reason)}")
        error
    end
  end

  defp load_linked_worker_ids(agent) do
    %{user: nil}
    |> Agents.list_linked_workers(agent.id)
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  defp persist_subtasks(invocation, normalized_plan) do
    # Convert depends_on_indices to depends_on_ids after insertion
    # First pass: create all subtasks without depends_on_ids
    attrs_list =
      Enum.map(normalized_plan, fn task ->
        %{
          description: task.description,
          position: task.position,
          assigned_agent_id: task.assigned_agent_id,
          acceptance_criteria: task.acceptance_criteria
        }
      end)

    case Orchestration.create_subtasks(invocation, attrs_list) do
      {:ok, subtasks} ->
        # Second pass: update depends_on_ids using actual subtask IDs
        update_dependencies(subtasks, normalized_plan)

      error ->
        error
    end
  end

  defp update_dependencies(subtasks, normalized_plan) do
    # Build index -> subtask_id map
    id_by_index = Map.new(subtasks, &{&1.position, &1.id})

    updated =
      Enum.zip(subtasks, normalized_plan)
      |> Enum.map(fn {subtask, plan_entry} ->
        dep_ids =
          (plan_entry.depends_on_indices || [])
          |> Enum.map(&Map.fetch!(id_by_index, &1))

        if dep_ids == [] do
          subtask
        else
          {:ok, updated} =
            subtask
            |> Ecto.Changeset.change(%{depends_on_ids: dep_ids})
            |> Summoner.Repo.update()

          updated
        end
      end)

    {:ok, updated}
  end

  defp dispatch_all(subtasks, manager_state) do
    invocation_id = List.first(subtasks).invocation_id
    max_concurrency = manager_state.agent.max_delegation_concurrency

    dispatch_loop(invocation_id, max_concurrency, manager_state, [])
  end

  defp dispatch_loop(invocation_id, max_concurrency, manager_state, results) do
    ready = Orchestration.ready_subtasks(invocation_id)

    if ready == [] do
      check_terminal_or_wait(invocation_id, max_concurrency, manager_state, results)
    else
      dispatch_batch(ready, invocation_id, max_concurrency, manager_state, results)
    end
  end

  defp check_terminal_or_wait(invocation_id, max_concurrency, manager_state, results) do
    all = Orchestration.list_subtasks(invocation_id)
    all_terminal? = Enum.all?(all, &(&1.status in [:completed, :failed, :skipped]))

    if all_terminal? do
      finalize_dispatch(all, results)
    else
      Process.sleep(500)
      dispatch_loop(invocation_id, max_concurrency, manager_state, results)
    end
  end

  defp finalize_dispatch(all_subtasks, results) do
    any_failed? = Enum.any?(all_subtasks, &(&1.status in [:failed, :skipped]))

    if any_failed? do
      {:error, {:subtasks_failed, results}}
    else
      {:ok, results}
    end
  end

  defp dispatch_batch(ready, invocation_id, max_concurrency, manager_state, results) do
    batch = Enum.take(ready, max_concurrency)

    batch_results =
      batch
      |> Task.async_stream(
        fn subtask ->
          notify_subtask_dispatched(manager_state, subtask)
          enriched = enrich_with_dependency_outputs(subtask)
          result = Dispatcher.dispatch(enriched, manager_state)
          notify_subtask_result(manager_state, subtask, result)
          result
        end,
        max_concurrency: max_concurrency,
        timeout: :infinity
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, nil, reason}
      end)

    # Handle dispatch-level failures (subtask never claimed, still :pending)
    needs_backoff? = handle_dispatch_failures(batch, batch_results, manager_state)

    if needs_backoff?, do: Process.sleep(@dispatch_retry_backoff_ms)

    new_results = results ++ batch_results
    dispatch_loop(invocation_id, max_concurrency, manager_state, new_results)
  end

  # Handles subtasks that failed at the dispatch level (never claimed/started).
  # Returns true if any subtask was requeued (needs backoff before next loop).
  defp handle_dispatch_failures(batch, batch_results, manager_state) do
    Enum.zip(batch, batch_results)
    |> Enum.filter(fn {_subtask, result} -> match?({:error, _, _}, result) end)
    |> Enum.reduce(false, fn {subtask, {:error, _, reason}}, needs_backoff? ->
      handle_single_dispatch_failure(subtask, reason, manager_state, needs_backoff?)
    end)
  end

  defp handle_single_dispatch_failure(subtask, reason, manager_state, needs_backoff?) do
    case Orchestration.get_subtask(subtask.id) do
      %Subtask{status: :pending} = current ->
        resolve_pending_failure(current, reason, manager_state, needs_backoff?)

      _other ->
        # Subtask was already claimed/finalized by dispatcher, nothing to do
        needs_backoff?
    end
  end

  defp resolve_pending_failure(subtask, reason, manager_state, needs_backoff?) do
    if FailurePolicy.can_retry?(subtask) do
      Logger.info(
        "Subtask #{subtask.id} dispatch failed (#{inspect(reason)}), requeuing (attempt #{subtask.retry_count + 1})"
      )

      Orchestration.requeue_subtask(subtask)
      true
    else
      Logger.warning(
        "Subtask #{subtask.id} dispatch failed (#{inspect(reason)}), exhausted retries"
      )

      Orchestration.fail_subtask(subtask)
      apply_failure_policy(manager_state, subtask)
      needs_backoff?
    end
  end

  defp apply_failure_policy(_manager_state, subtask) do
    invocation = Repo.get(Orchestration.Invocation, subtask.invocation_id)

    if invocation do
      FailurePolicy.apply_policy(:abort, invocation, subtask)
    end
  end

  defp notify_subtask_dispatched(%{on_subtask_dispatch: cb}, subtask) when is_function(cb, 1),
    do: cb.(subtask)

  defp notify_subtask_dispatched(_, _), do: :ok

  defp notify_subtask_result(%{on_subtask_result: cb}, subtask, result) when is_function(cb, 2),
    do: cb.(subtask, result)

  defp notify_subtask_result(_, _, _), do: :ok

  defp enrich_with_dependency_outputs(subtask) do
    case subtask.depends_on_ids do
      [] ->
        subtask

      dep_ids ->
        dep_outputs =
          dep_ids
          |> Enum.map(&Orchestration.get_subtask/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(&(&1.status == :completed && &1.worker_invocation_id != nil))
          |> Enum.map(fn dep ->
            invocation = Repo.get(Invocation, dep.worker_invocation_id)
            output = format_invocation_output(invocation)
            "- [Subtask #{dep.position}] #{dep.description}\n  Result: #{output}"
          end)

        if dep_outputs == [] do
          subtask
        else
          context =
            "## Previous subtask results\n" <> Enum.join(dep_outputs, "\n") <> "\n\n"

          %{subtask | description: context <> subtask.description}
        end
    end
  end

  defp format_invocation_output(nil), do: "(no output)"

  defp format_invocation_output(%{output: nil}), do: "(no output)"

  defp format_invocation_output(%{output: %{"result" => result}})
       when is_binary(result) and result != "",
       do: String.slice(result, 0, 2_000)

  defp format_invocation_output(%{output: %{"response" => response}})
       when is_binary(response) and response != "",
       do: String.slice(response, 0, 2_000)

  defp format_invocation_output(%{output: %{"response" => nil}}), do: "(no output)"
  defp format_invocation_output(%{output: %{"result" => nil}}), do: "(no output)"
  defp format_invocation_output(%{output: %{"result" => ""}}), do: "(no output)"
  defp format_invocation_output(%{output: %{"response" => ""}}), do: "(no output)"

  defp format_invocation_output(%{output: output}) when is_map(output),
    do: output |> Jason.encode!() |> String.slice(0, 2_000)

  defp format_invocation_output(_), do: "(no output)"
end
