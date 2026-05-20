defmodule Summoner.Services.Orchestration.SubtaskPlanTest do
  use ExUnit.Case, async: true

  alias Summoner.Services.Orchestration.SubtaskPlan

  describe "validate/2" do
    test "accepts a valid plan with no dependencies" do
      plan = [
        %{"description" => "Task A"},
        %{"description" => "Task B"}
      ]

      assert {:ok, normalized} = SubtaskPlan.validate(plan, MapSet.new())
      assert length(normalized) == 2
      assert Enum.at(normalized, 0).description == "Task A"
      assert Enum.at(normalized, 0).position == 0
      assert Enum.at(normalized, 1).position == 1
    end

    test "accepts a valid plan with linked workers" do
      worker_id = "worker-123"
      linked = MapSet.new([worker_id])

      plan = [
        %{"description" => "Task A", "worker_id" => worker_id}
      ]

      assert {:ok, [task]} = SubtaskPlan.validate(plan, linked)
      assert task.assigned_agent_id == worker_id
    end

    test "rejects plan with unlinked worker" do
      plan = [
        %{"description" => "Task A", "worker_id" => "unknown-worker"}
      ]

      assert {:error, {:unlinked_worker, 0, "unknown-worker"}} =
               SubtaskPlan.validate(plan, MapSet.new())
    end

    test "accepts valid dependencies" do
      plan = [
        %{"description" => "Task A"},
        %{"description" => "Task B", "depends_on" => [0]}
      ]

      assert {:ok, normalized} = SubtaskPlan.validate(plan, MapSet.new())
      assert Enum.at(normalized, 1).depends_on_indices == [0]
    end

    test "rejects invalid dependency index" do
      plan = [
        %{"description" => "Task A", "depends_on" => [5]}
      ]

      assert {:error, {:invalid_dependency_index, 0}} =
               SubtaskPlan.validate(plan, MapSet.new())
    end

    test "rejects cyclic dependencies" do
      plan = [
        %{"description" => "Task A", "depends_on" => [1]},
        %{"description" => "Task B", "depends_on" => [0]}
      ]

      assert {:error, :cyclic_dependencies} =
               SubtaskPlan.validate(plan, MapSet.new())
    end

    test "accepts diamond DAG (no cycle)" do
      plan = [
        %{"description" => "A"},
        %{"description" => "B", "depends_on" => [0]},
        %{"description" => "C", "depends_on" => [0]},
        %{"description" => "D", "depends_on" => [1, 2]}
      ]

      assert {:ok, normalized} = SubtaskPlan.validate(plan, MapSet.new())
      assert length(normalized) == 4
    end

    test "includes acceptance_criteria in normalized output" do
      plan = [
        %{"description" => "Task A", "acceptance_criteria" => "Must pass all tests"}
      ]

      assert {:ok, [task]} = SubtaskPlan.validate(plan, MapSet.new())
      assert task.acceptance_criteria == "Must pass all tests"
    end

    test "rejects non-list input" do
      assert {:error, :invalid_plan_format} =
               SubtaskPlan.validate("not a list", MapSet.new())
    end
  end

  describe "topological_sort/1" do
    test "sorts a simple linear chain" do
      graph = %{0 => [], 1 => [0], 2 => [1]}
      assert {:ok, sorted} = SubtaskPlan.topological_sort(graph)
      assert sorted == [0, 1, 2]
    end

    test "detects a cycle" do
      graph = %{0 => [1], 1 => [0]}
      assert :error = SubtaskPlan.topological_sort(graph)
    end

    test "handles independent nodes" do
      graph = %{0 => [], 1 => [], 2 => []}
      assert {:ok, sorted} = SubtaskPlan.topological_sort(graph)
      assert Enum.sort(sorted) == [0, 1, 2]
    end
  end
end
