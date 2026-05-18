defmodule Summoner.OrchestrationTest do
  use Summoner.DataCase

  alias Summoner.Orchestration

  import Summoner.AccountsFixtures
  import Summoner.ConversationsFixtures
  import Summoner.AgentsFixtures
  import Summoner.OrchestrationFixtures
  import Summoner.ProvidersFixtures
  import Summoner.WorkspacesFixtures

  defp create_context(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)
    conversation = conversation_fixture(scope, workspace.id, agent.id)

    %{
      scope: scope,
      workspace: workspace,
      provider: provider,
      agent: agent,
      conversation: conversation
    }
  end

  # -------------------------------------------------------------------
  # Invocations
  # -------------------------------------------------------------------

  describe "create_invocation/2" do
    setup :create_context

    test "creates an invocation with defaults", %{scope: scope, workspace: ws, agent: fam} do
      {:ok, invocation} =
        Orchestration.create_invocation(scope, %{
          workspace_id: ws.id,
          agent_id: fam.id
        })

      assert invocation.status == :queued
      assert invocation.depth == 0
      assert invocation.workspace_id == ws.id
      assert invocation.agent_id == fam.id
    end

    test "creates with conversation and input", %{
      scope: scope,
      workspace: ws,
      agent: fam,
      conversation: conv
    } do
      {:ok, invocation} =
        Orchestration.create_invocation(scope, %{
          workspace_id: ws.id,
          agent_id: fam.id,
          conversation_id: conv.id,
          input: %{"message" => "hello"}
        })

      assert invocation.conversation_id == conv.id
      assert invocation.input == %{"message" => "hello"}
    end

    test "creates child invocation with parent and depth", %{
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      parent = invocation_fixture(scope, ws.id, fam.id)

      {:ok, child} =
        Orchestration.create_invocation(scope, %{
          workspace_id: ws.id,
          agent_id: fam.id,
          parent_invocation_id: parent.id,
          depth: 1
        })

      assert child.parent_invocation_id == parent.id
      assert child.depth == 1
    end

    test "rejects depth greater than 3", %{scope: scope, workspace: ws, agent: fam} do
      {:error, changeset} =
        Orchestration.create_invocation(scope, %{
          workspace_id: ws.id,
          agent_id: fam.id,
          depth: 4
        })

      assert errors_on(changeset).depth
    end

    test "fails without required fields", %{scope: scope} do
      assert {:error, %Ecto.Changeset{}} = Orchestration.create_invocation(scope, %{})
    end
  end

  describe "get_invocation!/3" do
    setup :create_context

    test "returns invocation scoped to workspace", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)
      found = Orchestration.get_invocation!(scope, ws.id, inv.id)
      assert found.id == inv.id
    end

    test "raises when invocation is in different workspace", %{
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      inv = invocation_fixture(scope, ws.id, fam.id)
      other_ws = workspace_fixture(scope, name: "other-ws")

      assert_raise Ecto.NoResultsError, fn ->
        Orchestration.get_invocation!(scope, other_ws.id, inv.id)
      end
    end
  end

  describe "list_invocations/3" do
    setup :create_context

    test "returns invocations ordered by most recent", %{
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      i1 = invocation_fixture(scope, ws.id, fam.id)
      i2 = invocation_fixture(scope, ws.id, fam.id)

      result = Orchestration.list_invocations(scope, ws.id)
      assert [%{id: id2}, %{id: id1}] = result
      assert id1 == i1.id
      assert id2 == i2.id
    end

    test "filters by status", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)

      {:ok, _} =
        Orchestration.update_invocation_status(inv, :running, %{started_at: DateTime.utc_now()})

      _queued = invocation_fixture(scope, ws.id, fam.id)

      result = Orchestration.list_invocations(scope, ws.id, status: :running)
      assert length(result) == 1
      assert hd(result).id == inv.id
    end

    test "filters by agent_id", %{scope: scope, workspace: ws, provider: prov, agent: fam} do
      _inv = invocation_fixture(scope, ws.id, fam.id)
      fam2 = agent_fixture(scope, ws.id, prov.id, name: "other")
      inv2 = invocation_fixture(scope, ws.id, fam2.id)

      result = Orchestration.list_invocations(scope, ws.id, agent_id: fam2.id)
      assert length(result) == 1
      assert hd(result).id == inv2.id
    end

    test "does not return invocations from other workspaces", %{
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      _inv = invocation_fixture(scope, ws.id, fam.id)

      other_ws = workspace_fixture(scope, name: "other-ws")
      other_prov = provider_fixture(scope, other_ws.id)
      other_fam = agent_fixture(scope, other_ws.id, other_prov.id)
      _other_inv = invocation_fixture(scope, other_ws.id, other_fam.id)

      result = Orchestration.list_invocations(scope, ws.id)
      assert length(result) == 1
    end
  end

  describe "update_invocation_status/3" do
    setup :create_context

    test "transitions queued to running", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {:ok, updated} = Orchestration.update_invocation_status(inv, :running, %{started_at: now})
      assert updated.status == :running
      assert updated.started_at == now
    end

    test "transitions running to completed with end_reason and output", %{
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      inv = invocation_fixture(scope, ws.id, fam.id)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {:ok, running} = Orchestration.update_invocation_status(inv, :running, %{started_at: now})

      {:ok, completed} =
        Orchestration.update_invocation_status(running, :completed, %{
          end_reason: :completed,
          output: %{"result" => "done"},
          completed_at: now
        })

      assert completed.status == :completed
      assert completed.end_reason == :completed
      assert completed.output == %{"result" => "done"}
      assert completed.completed_at == now
    end

    test "transitions to failed with end_reason", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)

      {:ok, failed} =
        Orchestration.update_invocation_status(inv, :failed, %{
          end_reason: :failed,
          completed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

      assert failed.status == :failed
      assert failed.end_reason == :failed
    end

    test "transitions to cancelled", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)

      {:ok, cancelled} =
        Orchestration.update_invocation_status(inv, :cancelled, %{end_reason: :cancelled})

      assert cancelled.status == :cancelled
    end

    test "transitions to token_limit_reached", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)

      {:ok, limited} =
        Orchestration.update_invocation_status(inv, :completed, %{
          end_reason: :token_limit_reached
        })

      assert limited.end_reason == :token_limit_reached
    end
  end

  # -------------------------------------------------------------------
  # Steps
  # -------------------------------------------------------------------

  describe "add_step/1" do
    setup :create_context

    test "creates a step", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)

      {:ok, step} =
        Orchestration.add_step(%{
          invocation_id: inv.id,
          step_number: 1,
          reasoning: "I need to search for information",
          tool_name: "search",
          tool_input: %{"query" => "elixir genserver"},
          tool_output: %{"results" => ["..."]},
          status: :ok
        })

      assert step.step_number == 1
      assert step.reasoning == "I need to search for information"
      assert step.tool_name == "search"
      assert step.status == :ok
    end

    test "creates a step without tool (pure reasoning)", %{
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      inv = invocation_fixture(scope, ws.id, fam.id)

      {:ok, step} =
        Orchestration.add_step(%{
          invocation_id: inv.id,
          step_number: 1,
          reasoning: "The answer is clear from context"
        })

      assert step.tool_name == nil
      assert step.status == nil
    end

    test "fails without required fields" do
      assert {:error, %Ecto.Changeset{}} = Orchestration.add_step(%{})
    end

    test "rejects step_number <= 0", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)

      {:error, changeset} = Orchestration.add_step(%{invocation_id: inv.id, step_number: 0})
      assert errors_on(changeset).step_number
    end
  end

  describe "list_steps/1" do
    setup :create_context

    test "returns steps ordered by step_number", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)

      {:ok, _} =
        Orchestration.add_step(%{invocation_id: inv.id, step_number: 2, reasoning: "second"})

      {:ok, _} =
        Orchestration.add_step(%{invocation_id: inv.id, step_number: 1, reasoning: "first"})

      steps = Orchestration.list_steps(inv.id)
      assert [%{step_number: 1}, %{step_number: 2}] = steps
    end
  end

  # -------------------------------------------------------------------
  # Events
  # -------------------------------------------------------------------

  describe "add_event/1" do
    setup :create_context

    test "creates an event", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)

      {:ok, event} =
        Orchestration.add_event(%{
          invocation_id: inv.id,
          agent_id: fam.id,
          event_type: :tool_started,
          visibility: :public,
          summary: "Calling search tool",
          payload: %{"tool" => "search"}
        })

      assert event.event_type == :tool_started
      assert event.visibility == :public
      assert event.summary == "Calling search tool"
    end

    test "creates event without agent_id", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)

      {:ok, event} =
        Orchestration.add_event(%{
          invocation_id: inv.id,
          event_type: :completed,
          summary: "Invocation finished"
        })

      assert event.agent_id == nil
    end

    test "fails without required fields" do
      assert {:error, %Ecto.Changeset{}} = Orchestration.add_event(%{})
    end
  end

  describe "list_events/2" do
    setup :create_context

    test "returns events ordered chronologically", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)

      {:ok, _} = Orchestration.add_event(%{invocation_id: inv.id, event_type: :tool_started})
      {:ok, _} = Orchestration.add_event(%{invocation_id: inv.id, event_type: :tool_finished})

      events = Orchestration.list_events(inv.id)
      assert [%{event_type: :tool_started}, %{event_type: :tool_finished}] = events
    end

    test "filters by visibility", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)

      {:ok, _} =
        Orchestration.add_event(%{
          invocation_id: inv.id,
          event_type: :tool_started,
          visibility: :public
        })

      {:ok, _} =
        Orchestration.add_event(%{
          invocation_id: inv.id,
          event_type: :subtask_created,
          visibility: :internal
        })

      public = Orchestration.list_events(inv.id, visibility: :public)
      assert length(public) == 1

      internal = Orchestration.list_events(inv.id, visibility: :internal)
      assert length(internal) == 1
    end
  end

  # -------------------------------------------------------------------
  # Subtasks
  # -------------------------------------------------------------------

  describe "create_subtasks/2" do
    setup [:create_context]

    test "batch-creates subtasks for an invocation", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)

      {:ok, subtasks} =
        Orchestration.create_subtasks(inv, [
          %{description: "Task A", position: 0},
          %{description: "Task B", position: 1, acceptance_criteria: "Must be valid"}
        ])

      assert length(subtasks) == 2
      assert Enum.at(subtasks, 0).description == "Task A"
      assert Enum.at(subtasks, 0).status == :pending
      assert Enum.at(subtasks, 1).acceptance_criteria == "Must be valid"
    end

    test "sets depends_on_ids", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)
      {:ok, dep_id} = Nulid.generate()

      {:ok, [subtask]} =
        Orchestration.create_subtasks(inv, [
          %{description: "Dependent task", position: 0, depends_on_ids: [dep_id]}
        ])

      assert subtask.depends_on_ids == [dep_id]
    end

    test "rolls back on invalid subtask", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)

      assert {:error, _changeset} =
               Orchestration.create_subtasks(inv, [
                 %{description: "Valid", position: 0},
                 %{position: 1}
               ])

      # No subtasks should exist
      assert Orchestration.list_subtasks(inv.id) == []
    end
  end

  describe "claim_subtask/3" do
    setup [:create_context]

    test "claims a pending subtask", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)
      subtask = subtask_fixture(inv)

      worker_inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)

      assert {:ok, claimed} =
               Orchestration.claim_subtask(subtask.id, ctx.agent.id, worker_inv.id)

      assert claimed.status == :running
      assert claimed.assigned_agent_id == ctx.agent.id
      assert claimed.worker_invocation_id == worker_inv.id
    end

    test "rejects claiming an already-claimed subtask", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)
      subtask = subtask_fixture(inv)
      worker_inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)

      assert {:ok, _} = Orchestration.claim_subtask(subtask.id, ctx.agent.id, worker_inv.id)

      worker_inv2 = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)

      assert {:error, :already_claimed} =
               Orchestration.claim_subtask(subtask.id, ctx.agent.id, worker_inv2.id)
    end
  end

  describe "subtask status transitions" do
    setup [:create_context]

    test "complete_subtask/1", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)
      subtask = subtask_fixture(inv)

      assert {:ok, completed} = Orchestration.complete_subtask(subtask)
      assert completed.status == :completed
    end

    test "fail_subtask/1 increments retry_count", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)
      subtask = subtask_fixture(inv)

      assert {:ok, failed} = Orchestration.fail_subtask(subtask)
      assert failed.status == :failed
      assert failed.retry_count == 1
    end

    test "skip_subtask/1", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)
      subtask = subtask_fixture(inv)

      assert {:ok, skipped} = Orchestration.skip_subtask(subtask)
      assert skipped.status == :skipped
    end

    test "start_subtask/1", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)
      subtask = subtask_fixture(inv)

      assert {:ok, running} = Orchestration.start_subtask(subtask)
      assert running.status == :running
    end

    test "requeue_subtask/1 increments retry_count", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)
      subtask = subtask_fixture(inv)

      assert {:ok, requeued} = Orchestration.requeue_subtask(subtask)
      assert requeued.status == :pending
      assert requeued.retry_count == 1
    end
  end

  describe "ready_subtasks/1" do
    setup [:create_context]

    test "returns subtasks with no dependencies", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)

      {:ok, subtasks} =
        Orchestration.create_subtasks(inv, [
          %{description: "Independent A", position: 0},
          %{description: "Independent B", position: 1}
        ])

      ready = Orchestration.ready_subtasks(inv.id)
      assert length(ready) == 2

      assert Enum.map(ready, & &1.id) |> Enum.sort() ==
               Enum.map(subtasks, & &1.id) |> Enum.sort()
    end

    test "excludes subtasks with unmet dependencies", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)

      {:ok, [task_a, _task_b]} =
        Orchestration.create_subtasks(inv, [
          %{description: "Task A", position: 0},
          %{description: "Task B (depends on A)", position: 1, depends_on_ids: []}
        ])

      # Now create task_b with actual dependency on task_a
      {:ok, [task_c]} =
        Orchestration.create_subtasks(inv, [
          %{description: "Task C (depends on A)", position: 2, depends_on_ids: [task_a.id]}
        ])

      ready = Orchestration.ready_subtasks(inv.id)
      ready_ids = Enum.map(ready, & &1.id)

      # task_a and task_b are ready (no deps), task_c is not (depends on task_a)
      assert task_a.id in ready_ids
      refute task_c.id in ready_ids
    end

    test "includes subtasks whose dependencies are all terminal", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)

      {:ok, [task_a]} =
        Orchestration.create_subtasks(inv, [
          %{description: "Task A", position: 0}
        ])

      {:ok, [task_b]} =
        Orchestration.create_subtasks(inv, [
          %{description: "Task B (depends on A)", position: 1, depends_on_ids: [task_a.id]}
        ])

      # Complete task_a
      {:ok, _} = Orchestration.complete_subtask(task_a)

      ready = Orchestration.ready_subtasks(inv.id)
      ready_ids = Enum.map(ready, & &1.id)

      assert task_b.id in ready_ids
    end

    test "skips subtasks whose dependencies failed or were skipped", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)

      {:ok, [task_a]} =
        Orchestration.create_subtasks(inv, [
          %{description: "Task A", position: 0}
        ])

      {:ok, [task_b]} =
        Orchestration.create_subtasks(inv, [
          %{description: "Task B (depends on A)", position: 1, depends_on_ids: [task_a.id]}
        ])

      # Skip task_a — task_b should be auto-skipped, not returned as ready
      {:ok, _} = Orchestration.skip_subtask(task_a)

      ready = Orchestration.ready_subtasks(inv.id)
      assert ready == []

      # Verify task_b was auto-skipped
      updated_b = Orchestration.get_subtask(task_b.id)
      assert updated_b.status == :skipped
    end
  end

  describe "list_subtasks/1" do
    setup [:create_context]

    test "returns subtasks ordered by position", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)

      {:ok, _} =
        Orchestration.create_subtasks(inv, [
          %{description: "Third", position: 2},
          %{description: "First", position: 0},
          %{description: "Second", position: 1}
        ])

      subtasks = Orchestration.list_subtasks(inv.id)
      assert Enum.map(subtasks, & &1.description) == ["First", "Second", "Third"]
    end
  end
end
