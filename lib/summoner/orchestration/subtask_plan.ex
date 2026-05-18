defmodule Summoner.Orchestration.SubtaskPlan do
  @moduledoc """
  Validates and normalizes a subtask plan produced by a manager's LLM call.

  A subtask plan is a list of maps, each with:
  - `description` (required)
  - `worker_id` (optional — ID of the linked worker to assign)
  - `depends_on` (optional — list of subtask indices that must complete first)
  - `acceptance_criteria` (optional)

  Validation checks:
  - Worker IDs must be linked to the manager
  - Dependencies must form a valid DAG (no cycles)
  - Dependencies must reference valid subtask indices
  """

  @doc """
  Validates a subtask plan.

  `plan` is a list of maps from the LLM's JSON output.
  `linked_worker_ids` is a MapSet of agent IDs linked to the manager.

  Returns `{:ok, normalized_plan}` or `{:error, reason}`.
  """
  def validate(plan, linked_worker_ids) when is_list(plan) do
    with :ok <- validate_workers(plan, linked_worker_ids),
         :ok <- validate_dependencies(plan),
         :ok <- validate_no_cycles(plan) do
      {:ok, normalize(plan)}
    end
  end

  def validate(_, _), do: {:error, :invalid_plan_format}

  defp validate_workers(plan, linked_worker_ids) do
    invalid =
      plan
      |> Enum.with_index()
      |> Enum.filter(fn {task, _i} ->
        worker_id = Map.get(task, "worker_id")
        worker_id != nil && !MapSet.member?(linked_worker_ids, worker_id)
      end)

    case invalid do
      [] -> :ok
      [{task, i} | _] -> {:error, {:unlinked_worker, i, Map.get(task, "worker_id")}}
    end
  end

  defp validate_dependencies(plan) do
    max_index = length(plan) - 1

    invalid =
      plan
      |> Enum.with_index()
      |> Enum.find(fn {task, _i} ->
        deps = Map.get(task, "depends_on", [])
        Enum.any?(deps, &(&1 < 0 || &1 > max_index))
      end)

    case invalid do
      nil -> :ok
      {_task, i} -> {:error, {:invalid_dependency_index, i}}
    end
  end

  defp validate_no_cycles(plan) do
    graph =
      plan
      |> Enum.with_index()
      |> Map.new(fn {task, i} -> {i, Map.get(task, "depends_on", [])} end)

    case topological_sort(graph) do
      {:ok, _} -> :ok
      :error -> {:error, :cyclic_dependencies}
    end
  end

  @doc """
  Topological sort of a dependency graph.

  `graph` is a map of `index => [dependency_indices]`.
  Returns `{:ok, sorted_indices}` or `:error` if cyclic.
  """
  def topological_sort(graph) do
    do_topo_sort(Map.keys(graph), graph, MapSet.new(), MapSet.new(), [])
  end

  defp do_topo_sort([], _graph, _visited, _in_progress, acc), do: {:ok, Enum.reverse(acc)}

  defp do_topo_sort([node | rest], graph, visited, in_progress, acc) do
    if MapSet.member?(visited, node) do
      do_topo_sort(rest, graph, visited, in_progress, acc)
    else
      case visit(node, graph, visited, in_progress, acc) do
        {:ok, visited, acc} -> do_topo_sort(rest, graph, visited, in_progress, acc)
        :error -> :error
      end
    end
  end

  defp visit(node, graph, visited, in_progress, acc) do
    if MapSet.member?(in_progress, node) do
      :error
    else
      in_progress = MapSet.put(in_progress, node)
      deps = Map.get(graph, node, [])

      case visit_deps(deps, graph, visited, in_progress, acc) do
        {:ok, visited, acc} ->
          {:ok, MapSet.put(visited, node), [node | acc]}

        :error ->
          :error
      end
    end
  end

  defp visit_deps([], _graph, visited, _in_progress, acc), do: {:ok, visited, acc}

  defp visit_deps([dep | rest], graph, visited, in_progress, acc) do
    if MapSet.member?(visited, dep) do
      visit_deps(rest, graph, visited, in_progress, acc)
    else
      case visit(dep, graph, visited, in_progress, acc) do
        {:ok, visited, acc} -> visit_deps(rest, graph, visited, in_progress, acc)
        :error -> :error
      end
    end
  end

  defp normalize(plan) do
    plan
    |> Enum.with_index()
    |> Enum.map(fn {task, i} ->
      %{
        description: Map.fetch!(task, "description"),
        position: i,
        assigned_agent_id: Map.get(task, "worker_id"),
        acceptance_criteria: Map.get(task, "acceptance_criteria"),
        depends_on_indices: Map.get(task, "depends_on", [])
      }
    end)
  end
end
