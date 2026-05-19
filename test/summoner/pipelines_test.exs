defmodule Summoner.Adapters.Persistence.PipelinesTest do
  use Summoner.DataCase

  alias Summoner.Adapters.Persistence.Pipelines

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent_a = agent_fixture(scope, workspace.id, provider.id, %{name: "Agent A"})
    agent_b = agent_fixture(scope, workspace.id, provider.id, %{name: "Agent B"})

    manager =
      agent_fixture(scope, workspace.id, provider.id, %{name: "Manager"})

    %{
      scope: scope,
      workspace: workspace,
      agent_a: agent_a,
      agent_b: agent_b,
      manager: manager
    }
  end

  describe "create_pipeline/2" do
    test "creates a simple manual pipeline", ctx do
      assert {:ok, pipeline} =
               Pipelines.create_pipeline(ctx.scope, %{
                 name: "My Pipeline",
                 workspace_id: ctx.workspace.id
               })

      assert pipeline.name == "My Pipeline"
      assert pipeline.mode == :simple
      assert pipeline.trigger_type == :manual
    end

    test "creates a scheduled pipeline with cron", ctx do
      assert {:ok, pipeline} =
               Pipelines.create_pipeline(ctx.scope, %{
                 name: "Scheduled",
                 workspace_id: ctx.workspace.id,
                 trigger_type: :scheduled,
                 cron_expression: "*/5 * * * *"
               })

      assert pipeline.trigger_type == :scheduled
      assert pipeline.cron_expression == "*/5 * * * *"
    end

    test "rejects scheduled pipeline without cron", ctx do
      assert {:error, changeset} =
               Pipelines.create_pipeline(ctx.scope, %{
                 name: "Bad",
                 workspace_id: ctx.workspace.id,
                 trigger_type: :scheduled
               })

      assert errors_on(changeset).cron_expression
    end

    test "rejects invalid cron expression", ctx do
      assert {:error, changeset} =
               Pipelines.create_pipeline(ctx.scope, %{
                 name: "Bad",
                 workspace_id: ctx.workspace.id,
                 trigger_type: :scheduled,
                 cron_expression: "not a cron"
               })

      assert errors_on(changeset).cron_expression
    end

    test "creates an orchestrated pipeline with manager", ctx do
      assert {:ok, pipeline} =
               Pipelines.create_pipeline(ctx.scope, %{
                 name: "Orchestrated",
                 workspace_id: ctx.workspace.id,
                 mode: :orchestrated,
                 orchestrator_agent_id: ctx.manager.id
               })

      assert pipeline.mode == :orchestrated
      assert pipeline.orchestrator_agent_id == ctx.manager.id
    end

    test "rejects orchestrated pipeline without orchestrator", ctx do
      assert {:error, changeset} =
               Pipelines.create_pipeline(ctx.scope, %{
                 name: "Bad Orch",
                 workspace_id: ctx.workspace.id,
                 mode: :orchestrated
               })

      assert errors_on(changeset).orchestrator_agent_id
    end

    test "rejects duplicate name in same workspace", ctx do
      {:ok, _} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "Dupe",
          workspace_id: ctx.workspace.id
        })

      assert {:error, changeset} =
               Pipelines.create_pipeline(ctx.scope, %{
                 name: "Dupe",
                 workspace_id: ctx.workspace.id
               })

      assert errors_on(changeset).workspace_id
    end
  end

  describe "list_pipelines/2" do
    test "lists pipelines for a workspace", ctx do
      {:ok, _} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "Pipeline 1",
          workspace_id: ctx.workspace.id
        })

      pipelines = Pipelines.list_pipelines(ctx.scope, ctx.workspace.id)
      assert length(pipelines) == 1
    end
  end

  describe "list_scheduled_pipelines/0" do
    test "returns only scheduled pipelines", ctx do
      {:ok, _} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "Manual",
          workspace_id: ctx.workspace.id
        })

      {:ok, _} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "Scheduled",
          workspace_id: ctx.workspace.id,
          trigger_type: :scheduled,
          cron_expression: "0 * * * *"
        })

      scheduled = Pipelines.list_scheduled_pipelines()
      assert length(scheduled) == 1
      assert hd(scheduled).name == "Scheduled"
    end
  end

  describe "add_stage/2" do
    test "adds a stage without instruction", ctx do
      {:ok, pipeline} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "Test",
          workspace_id: ctx.workspace.id
        })

      assert {:ok, stage} =
               Pipelines.add_stage(ctx.scope, %{
                 pipeline_id: pipeline.id,
                 agent_id: ctx.agent_a.id,
                 position: 0
               })

      assert stage.position == 0
      assert stage.instruction == nil
    end

    test "adds a stage with instruction", ctx do
      {:ok, pipeline} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "Test",
          workspace_id: ctx.workspace.id
        })

      assert {:ok, stage} =
               Pipelines.add_stage(ctx.scope, %{
                 pipeline_id: pipeline.id,
                 agent_id: ctx.agent_a.id,
                 position: 0,
                 instruction: "Summarize the input text"
               })

      assert stage.instruction == "Summarize the input text"
    end

    test "allows same agent in multiple stages", ctx do
      {:ok, pipeline} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "Test",
          workspace_id: ctx.workspace.id
        })

      {:ok, _} =
        Pipelines.add_stage(ctx.scope, %{
          pipeline_id: pipeline.id,
          agent_id: ctx.agent_a.id,
          position: 0
        })

      assert {:ok, _} =
               Pipelines.add_stage(ctx.scope, %{
                 pipeline_id: pipeline.id,
                 agent_id: ctx.agent_a.id,
                 position: 1
               })
    end

    test "rejects duplicate position in same pipeline", ctx do
      {:ok, pipeline} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "Test",
          workspace_id: ctx.workspace.id
        })

      {:ok, _} =
        Pipelines.add_stage(ctx.scope, %{
          pipeline_id: pipeline.id,
          agent_id: ctx.agent_a.id,
          position: 0
        })

      assert {:error, changeset} =
               Pipelines.add_stage(ctx.scope, %{
                 pipeline_id: pipeline.id,
                 agent_id: ctx.agent_b.id,
                 position: 0
               })

      assert errors_on(changeset).pipeline_id
    end
  end

  describe "update_stage/3" do
    test "updates stage instruction", ctx do
      {:ok, pipeline} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "Test",
          workspace_id: ctx.workspace.id
        })

      {:ok, stage} =
        Pipelines.add_stage(ctx.scope, %{
          pipeline_id: pipeline.id,
          agent_id: ctx.agent_a.id,
          position: 0
        })

      assert {:ok, updated} =
               Pipelines.update_stage(ctx.scope, stage, %{instruction: "Translate to French"})

      assert updated.instruction == "Translate to French"
    end
  end

  describe "list_stages/1" do
    test "returns stages ordered by position", ctx do
      {:ok, pipeline} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "Test",
          workspace_id: ctx.workspace.id
        })

      {:ok, _} =
        Pipelines.add_stage(ctx.scope, %{
          pipeline_id: pipeline.id,
          agent_id: ctx.agent_b.id,
          position: 1
        })

      {:ok, _} =
        Pipelines.add_stage(ctx.scope, %{
          pipeline_id: pipeline.id,
          agent_id: ctx.agent_a.id,
          position: 0
        })

      stages = Pipelines.list_stages(pipeline.id)
      assert Enum.map(stages, & &1.position) == [0, 1]
      assert Enum.map(stages, & &1.agent.name) == ["Agent A", "Agent B"]
    end
  end

  describe "delete_pipeline/2" do
    test "deletes a pipeline and its stages", ctx do
      {:ok, pipeline} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "To Delete",
          workspace_id: ctx.workspace.id
        })

      {:ok, _} =
        Pipelines.add_stage(ctx.scope, %{
          pipeline_id: pipeline.id,
          agent_id: ctx.agent_a.id,
          position: 0
        })

      assert {:ok, _} = Pipelines.delete_pipeline(ctx.scope, pipeline)
      assert Pipelines.list_stages(pipeline.id) == []
    end
  end

  # -------------------------------------------------------------------
  # Pipeline Runs
  # -------------------------------------------------------------------

  defp create_pipeline_with_stages(ctx) do
    {:ok, pipeline} =
      Pipelines.create_pipeline(ctx.scope, %{
        name: "Runnable",
        workspace_id: ctx.workspace.id
      })

    {:ok, _} =
      Pipelines.add_stage(ctx.scope, %{
        pipeline_id: pipeline.id,
        agent_id: ctx.agent_a.id,
        position: 0
      })

    {:ok, _} =
      Pipelines.add_stage(ctx.scope, %{
        pipeline_id: pipeline.id,
        agent_id: ctx.agent_b.id,
        position: 1
      })

    pipeline
  end

  describe "create_run/1" do
    test "creates a pipeline run", ctx do
      pipeline = create_pipeline_with_stages(ctx)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      assert {:ok, run} =
               Pipelines.create_run(%{
                 pipeline_id: pipeline.id,
                 workspace_id: ctx.workspace.id,
                 input: "hello",
                 started_at: now
               })

      assert run.status == :running
      assert run.input == "hello"
      assert run.pipeline_id == pipeline.id
    end
  end

  describe "update_run/2" do
    test "completes a run with output", ctx do
      pipeline = create_pipeline_with_stages(ctx)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {:ok, run} =
        Pipelines.create_run(%{
          pipeline_id: pipeline.id,
          workspace_id: ctx.workspace.id,
          started_at: now
        })

      assert {:ok, updated} =
               Pipelines.update_run(run, %{
                 status: :completed,
                 output: "done",
                 completed_at: now
               })

      assert updated.status == :completed
      assert updated.output == "done"
    end

    test "fails a run with error", ctx do
      pipeline = create_pipeline_with_stages(ctx)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {:ok, run} =
        Pipelines.create_run(%{
          pipeline_id: pipeline.id,
          workspace_id: ctx.workspace.id,
          started_at: now
        })

      assert {:ok, updated} =
               Pipelines.update_run(run, %{status: :failed, error: "boom", completed_at: now})

      assert updated.status == :failed
      assert updated.error == "boom"
    end
  end

  describe "list_runs/1" do
    test "lists runs for a pipeline, most recent first", ctx do
      pipeline = create_pipeline_with_stages(ctx)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      earlier = DateTime.add(now, -60, :second)

      {:ok, _run1} =
        Pipelines.create_run(%{
          pipeline_id: pipeline.id,
          workspace_id: ctx.workspace.id,
          started_at: earlier
        })

      {:ok, _run2} =
        Pipelines.create_run(%{
          pipeline_id: pipeline.id,
          workspace_id: ctx.workspace.id,
          started_at: now
        })

      runs = Pipelines.list_runs(pipeline.id)
      assert length(runs) == 2
      assert hd(runs).started_at == now
    end
  end

  describe "create_run_stage/1 and update_run_stage/2" do
    test "creates and completes a run stage", ctx do
      pipeline = create_pipeline_with_stages(ctx)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {:ok, run} =
        Pipelines.create_run(%{
          pipeline_id: pipeline.id,
          workspace_id: ctx.workspace.id,
          started_at: now
        })

      assert {:ok, stage} =
               Pipelines.create_run_stage(%{
                 pipeline_run_id: run.id,
                 agent_id: ctx.agent_a.id,
                 position: 0,
                 status: :running,
                 input: "stage input",
                 started_at: now
               })

      assert stage.status == :running

      assert {:ok, updated} =
               Pipelines.update_run_stage(stage, %{
                 status: :completed,
                 output: "stage output",
                 completed_at: now
               })

      assert updated.status == :completed
      assert updated.output == "stage output"
    end

    test "creates a skipped run stage", ctx do
      pipeline = create_pipeline_with_stages(ctx)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {:ok, run} =
        Pipelines.create_run(%{
          pipeline_id: pipeline.id,
          workspace_id: ctx.workspace.id,
          started_at: now
        })

      assert {:ok, stage} =
               Pipelines.create_run_stage(%{
                 pipeline_run_id: run.id,
                 agent_id: ctx.agent_b.id,
                 position: 1,
                 status: :skipped
               })

      assert stage.status == :skipped
    end
  end

  describe "get_run!/1" do
    test "returns a run with stages preloaded", ctx do
      pipeline = create_pipeline_with_stages(ctx)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {:ok, run} =
        Pipelines.create_run(%{
          pipeline_id: pipeline.id,
          workspace_id: ctx.workspace.id,
          started_at: now
        })

      {:ok, _} =
        Pipelines.create_run_stage(%{
          pipeline_run_id: run.id,
          agent_id: ctx.agent_a.id,
          position: 0,
          status: :completed,
          started_at: now,
          completed_at: now
        })

      fetched = Pipelines.get_run!(run.id)
      assert length(fetched.stages) == 1
      assert hd(fetched.stages).agent.name == "Agent A"
    end
  end

  # -------------------------------------------------------------------
  # Persistent pipeline conversations
  # -------------------------------------------------------------------

  describe "ensure_conversation/1" do
    test "creates a new conversation for a pipeline without one", ctx do
      {:ok, pipeline} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "Quest With Conv",
          workspace_id: ctx.workspace.id
        })

      {:ok, _stage} =
        Pipelines.add_stage(ctx.scope, %{
          pipeline_id: pipeline.id,
          agent_id: ctx.agent_a.id,
          position: 0
        })

      pipeline = Pipelines.get_pipeline!(ctx.scope, ctx.workspace.id, pipeline.id)

      assert is_nil(pipeline.conversation_id)
      assert {:ok, conversation_id} = Pipelines.ensure_conversation(pipeline)
      assert is_binary(conversation_id)

      # Reload pipeline — conversation_id should be persisted
      updated = Pipelines.get_pipeline!(ctx.scope, ctx.workspace.id, pipeline.id)
      assert updated.conversation_id == conversation_id
    end

    test "returns existing conversation_id if already set", ctx do
      {:ok, pipeline} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "Quest Existing",
          workspace_id: ctx.workspace.id
        })

      {:ok, _stage} =
        Pipelines.add_stage(ctx.scope, %{
          pipeline_id: pipeline.id,
          agent_id: ctx.agent_a.id,
          position: 0
        })

      pipeline = Pipelines.get_pipeline!(ctx.scope, ctx.workspace.id, pipeline.id)
      {:ok, conv_id} = Pipelines.ensure_conversation(pipeline)

      # Call again — should return the same id without creating a new conversation
      updated = Pipelines.get_pipeline!(ctx.scope, ctx.workspace.id, pipeline.id)
      assert {:ok, ^conv_id} = Pipelines.ensure_conversation(updated)
    end

    test "returns error when pipeline has no stages", ctx do
      {:ok, pipeline} =
        Pipelines.create_pipeline(ctx.scope, %{
          name: "Empty Quest",
          workspace_id: ctx.workspace.id
        })

      pipeline = Pipelines.get_pipeline!(ctx.scope, ctx.workspace.id, pipeline.id)
      assert {:error, :no_stages} = Pipelines.ensure_conversation(pipeline)
    end
  end
end
