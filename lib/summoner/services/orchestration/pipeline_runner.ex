defmodule Summoner.Services.Orchestration.PipelineRunner do
  @moduledoc """
  Executes a pipeline — running stages based on the pipeline's mode.

  ## Simple mode

  Stages run sequentially. Each stage delegates to its agent with a
  task instruction. The agent's output feeds the next stage's input.

  ## Orchestrated mode

  A designated manager agent receives the pipeline stages as a subtask
  plan and uses its delegation system to execute them.

  ## Run Tracking

  Each execution creates a `PipelineRun` with `PipelineRunStage` records
  tracking per-stage input, output, status, and timing.
  """

  require Logger

  alias Summoner.Adapters.Persistence.Agents
  alias Summoner.Adapters.Persistence.Conversations
  alias Summoner.Adapters.Persistence.Orchestration
  alias Summoner.Adapters.Persistence.Pipelines
  alias Summoner.Domain.Events.{InvocationCompleted, InvocationFailed, InvocationStarted}
  alias Summoner.Domain.Events.{PipelineRunStatus, PipelineStageInvocation, PipelineStageStatus}
  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Ports.Events
  alias Summoner.Services.Agents.Server
  alias Summoner.Services.Orchestration.Manager

  @stage_timeout :timer.minutes(10)

  @doc """
  Runs a pipeline from the given starting position.

  Returns `{:ok, run}` or `{:error, reason}`.
  """
  def run(pipeline_invocation, pipeline_id, initial_input, opts \\ []) do
    pipeline =
      Pipelines.get_pipeline!(%{user: nil}, pipeline_invocation.workspace_id, pipeline_id)

    # Ensure the pipeline has a persistent conversation for cross-run context
    conversation_id =
      case Pipelines.ensure_conversation(pipeline) do
        {:ok, id} -> id
        {:error, _} -> nil
      end

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {:ok, run} =
      Pipelines.create_run(%{
        pipeline_id: pipeline.id,
        workspace_id: pipeline_invocation.workspace_id,
        input: initial_input,
        started_at: now
      })

    broadcast_run_status(pipeline_invocation.workspace_id, pipeline.id, run.id, :running)

    # Record the run input as a user message in the conversation
    if conversation_id do
      Conversations.add_message(%{
        conversation_id: conversation_id,
        role: :user,
        content: "## Quest Run\n\n#{initial_input}",
        visibility: :internal,
        kind: :chat
      })
    end

    result =
      case pipeline.mode do
        :simple ->
          run_simple(pipeline_invocation, pipeline, run, initial_input, conversation_id, opts)

        :orchestrated ->
          run_orchestrated(pipeline_invocation, pipeline, run, initial_input)
      end

    case result do
      {:ok, output} ->
        complete_run(run, output)

      {:error, reason} ->
        fail_run(run, reason)
    end
  end

  # -------------------------------------------------------------------
  # Simple mode — sequential delegation
  # -------------------------------------------------------------------

  defp run_simple(pipeline_invocation, pipeline, run, initial_input, conversation_id, opts) do
    start_pos = Keyword.get(opts, :start_position, 0)

    remaining_stages =
      pipeline.stages
      |> Enum.filter(&(&1.position >= start_pos))
      |> Enum.sort_by(& &1.position)

    run_stages(remaining_stages, pipeline_invocation, run, %{}, initial_input, conversation_id)
  end

  defp run_stages([], pipeline_invocation, _run, _results_by_position, last_output, _conv_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {:ok, _} =
      Orchestration.update_invocation_status(pipeline_invocation, :completed, %{
        end_reason: :completed,
        output: %{"result" => last_output},
        completed_at: now
      })

    {:ok, last_output}
  end

  defp run_stages(
         [stage | rest],
         pipeline_invocation,
         run,
         results_by_position,
         input,
         conversation_id
       ) do
    agent = stage.agent

    {:ok, pipeline_invocation} =
      Orchestration.update_invocation_status(pipeline_invocation, :running, %{
        pipeline_stage_position: stage.position
      })

    emit_stage_event(pipeline_invocation, stage, agent, :pipeline_stage_started, rest == [])

    # Create run stage record
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {:ok, run_stage} =
      Pipelines.create_run_stage(
        %{
          pipeline_run_id: run.id,
          agent_id: agent.id,
          position: stage.position,
          status: :running,
          input: input,
          started_at: now
        }
        |> Map.merge(Agent.inference_snapshot(agent))
      )

    broadcast_stage_status(
      pipeline_invocation.workspace_id,
      run.pipeline_id,
      run.id,
      stage.position,
      :running
    )

    case execute_stage(
           stage,
           pipeline_invocation,
           run,
           input,
           results_by_position,
           conversation_id
         ) do
      {:ok, output} ->
        complete_run_stage(run_stage, output)

        broadcast_stage_status(
          pipeline_invocation.workspace_id,
          run.pipeline_id,
          run.id,
          stage.position,
          :completed
        )

        results_by_position = Map.put(results_by_position, stage.position, output)
        emit_stage_event(pipeline_invocation, stage, agent, :pipeline_stage_completed, false)
        run_stages(rest, pipeline_invocation, run, results_by_position, output, conversation_id)

      {:error, reason} ->
        fail_run_stage(run_stage, reason)

        broadcast_stage_status(
          pipeline_invocation.workspace_id,
          run.pipeline_id,
          run.id,
          stage.position,
          :failed
        )

        # Mark remaining stages as skipped
        skip_remaining_stages(rest, run)
        emit_stage_event(pipeline_invocation, stage, agent, :pipeline_stage_completed, false)
        halt_pipeline(pipeline_invocation, stage, reason)
    end
  end

  defp execute_stage(
         stage,
         _pipeline_invocation,
         run,
         input,
         results_by_position,
         conversation_id
       ) do
    agent = stage.agent
    workspace_id = stage.agent.workspace_id
    message = build_stage_message(stage, input, results_by_position)

    # Subscribe to agent topic to receive completion broadcasts
    Events.subscribe({:agent, workspace_id, agent.id})

    with :ok <- Server.ensure_started(workspace_id, agent.id) do
      # Fire async — pass conversation_id for persistent context
      Server.invoke_async(workspace_id, agent.id, %{
        conversation_id: conversation_id,
        message: message,
        scope: %{user: nil},
        react_opts: %{pipeline_stage: true}
      })

      # Wait for the agent to finish and extract output
      await_agent_completion(workspace_id, agent.id, run, stage.position)
    end
  end

  defp await_agent_completion(workspace_id, agent_id, run, position) do
    receive do
      %InvocationCompleted{invocation_id: invocation_id} ->
        handle_stage_completion(
          workspace_id,
          agent_id,
          invocation_id,
          run,
          position
        )

      %InvocationFailed{invocation_id: invocation_id, output: output} ->
        handle_stage_failure(
          workspace_id,
          agent_id,
          invocation_id,
          output,
          run,
          position
        )

      %InvocationStarted{invocation_id: invocation_id} ->
        broadcast_stage_invocation(workspace_id, run.pipeline_id, run.id, position, invocation_id)
        await_agent_completion(workspace_id, agent_id, run, position)

      %struct{} when struct in [InvocationCompleted, InvocationFailed, InvocationStarted] ->
        await_agent_completion(workspace_id, agent_id, run, position)
    after
      @stage_timeout ->
        Events.unsubscribe({:agent, workspace_id, agent_id})
        {:error, :stage_timeout}
    end
  end

  defp handle_stage_completion(workspace_id, agent_id, invocation_id, run, position) do
    invocation = Orchestration.get_invocation_by_id(invocation_id)

    if matches_stage_agent?(invocation, workspace_id, agent_id) do
      Events.unsubscribe({:agent, workspace_id, agent_id})
      {:ok, extract_invocation_output(invocation)}
    else
      await_agent_completion(workspace_id, agent_id, run, position)
    end
  end

  defp handle_stage_failure(workspace_id, agent_id, invocation_id, output, run, pos) do
    invocation = Orchestration.get_invocation_by_id(invocation_id)

    if matches_stage_agent?(invocation, workspace_id, agent_id) do
      Events.unsubscribe({:agent, workspace_id, agent_id})
      error = extract_failure_reason(invocation, output)
      {:error, error}
    else
      await_agent_completion(workspace_id, agent_id, run, pos)
    end
  end

  defp matches_stage_agent?(nil, _workspace_id, _agent_id), do: false

  defp matches_stage_agent?(invocation, workspace_id, agent_id) do
    invocation.workspace_id == workspace_id && invocation.agent_id == agent_id
  end

  defp extract_failure_reason(invocation, output) do
    cond do
      is_map(output) && output["error"] -> output["error"]
      is_map(invocation.output) -> invocation.output["error"] || "agent failed"
      true -> "agent failed"
    end
  end

  defp extract_invocation_output(nil), do: ""

  defp extract_invocation_output(invocation) do
    case invocation.output do
      %{"response" => response} -> response
      %{"result" => result} -> result
      _ -> ""
    end
  end

  @complete_instruction """
  IMPORTANT: When you have finished your task, you MUST call the __complete__ tool \
  with your final result. Do NOT simply write your answer as text. \
  Always submit your result using the __complete__ tool.\
  """

  defp build_stage_message(stage, input, results_by_position) do
    base =
      case stage.instruction do
        nil -> input
        "" -> input
        instruction -> "#{instruction}\n\n---\n\n#{input}"
      end

    # Inject results from explicit dependencies if present
    base_with_deps = inject_dependency_results(base, stage, results_by_position)

    "#{base_with_deps}\n\n#{@complete_instruction}"
  end

  defp inject_dependency_results(base, stage, results_by_position) do
    deps = stage.depends_on_positions || []

    case deps do
      [] ->
        base

      positions ->
        dep_context =
          positions
          |> Enum.sort()
          |> Enum.map(&format_dep_result(&1, results_by_position))
          |> Enum.reject(&is_nil/1)
          |> Enum.join("\n\n---\n\n")

        case dep_context do
          "" -> base
          context -> "#{base}\n\n## Previous stage results\n\n#{context}"
        end
    end
  end

  defp format_dep_result(pos, results_by_position) do
    case Map.get(results_by_position, pos) do
      nil -> nil
      result -> "## Result from stage #{pos}\n\n#{result}"
    end
  end

  # -------------------------------------------------------------------
  # Run stage tracking helpers
  # -------------------------------------------------------------------

  defp complete_run_stage(run_stage, output) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Pipelines.update_run_stage(run_stage, %{status: :completed, output: output, completed_at: now})
  end

  defp fail_run_stage(run_stage, reason) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Pipelines.update_run_stage(run_stage, %{
      status: :failed,
      error: inspect(reason),
      completed_at: now
    })
  end

  defp skip_remaining_stages(stages, run) do
    Enum.each(stages, fn stage ->
      Pipelines.create_run_stage(
        %{
          pipeline_run_id: run.id,
          agent_id: stage.agent.id,
          position: stage.position,
          status: :skipped
        }
        |> Map.merge(Agent.inference_snapshot(stage.agent))
      )
    end)
  end

  defp format_pipeline_results(results) do
    results
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {result, idx} ->
      format_single_result(result, idx)
    end)
  end

  defp format_single_result({:ok, _id, :completed, output}, idx) when is_map(output) do
    content = output["result"] || output["response"] || Jason.encode!(output)
    "Stage #{idx}: completed — #{String.slice(to_string(content), 0, 500)}"
  end

  defp format_single_result({:ok, _id, :completed, _}, idx), do: "Stage #{idx}: completed"

  defp format_single_result({:ok, _id, :failed, reason}, idx),
    do: "Stage #{idx}: failed — #{inspect(reason)}"

  defp format_single_result({:error, _id, reason}, idx),
    do: "Stage #{idx}: error — #{inspect(reason)}"

  defp format_single_result(result, idx), do: "Stage #{idx}: #{inspect(result)}"

  defp complete_run(run, output) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {:ok, run} =
      Pipelines.update_run(run, %{status: :completed, output: output, completed_at: now})

    broadcast_run_status(run.workspace_id, run.pipeline_id, run.id, :completed)
    {:ok, run}
  end

  defp fail_run(run, reason) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {:ok, run} =
      Pipelines.update_run(run, %{status: :failed, error: inspect(reason), completed_at: now})

    broadcast_run_status(run.workspace_id, run.pipeline_id, run.id, :failed)
    {:error, reason}
  end

  # -------------------------------------------------------------------
  # Orchestrated mode — manager delegation
  # -------------------------------------------------------------------

  defp run_orchestrated(pipeline_invocation, pipeline, run, initial_input) do
    orchestrator = Agents.get_agent_with_provider!(pipeline.orchestrator_agent_id)
    workspace_id = pipeline_invocation.workspace_id

    Logger.info("Starting orchestrated pipeline #{pipeline.id}")
    ensure_agent_links(orchestrator, pipeline.stages)
    Logger.info("Agent links ensured, building plan")
    plan = build_plan_from_stages(pipeline.stages)
    Logger.info("Plan built with #{length(plan)} stages")

    # Create run stage records upfront (one per pipeline stage)
    run_stages_by_position = create_orchestrated_run_stages(run, pipeline.stages)

    {:ok, manager_inv} =
      Orchestration.create_invocation(%{user: nil}, %{
        workspace_id: workspace_id,
        agent_id: orchestrator.id,
        conversation_id: pipeline_invocation.conversation_id,
        parent_invocation_id: pipeline_invocation.id,
        pipeline_id: pipeline_invocation.pipeline_id,
        depth: (pipeline_invocation.depth || 0) + 1,
        status: :running,
        input: %{"message" => initial_input},
        started_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
        provider_name: orchestrator.local_agent.provider.name,
        model_name: orchestrator.local_agent.model
      })

    manager_state = %{
      agent: orchestrator,
      active_tasks: %{},
      pending_cancel: MapSet.new(),
      tool_executor: nil,
      adapter: nil,
      on_subtask_dispatch: fn subtask ->
        update_orchestrated_stage(
          run_stages_by_position,
          run,
          subtask.position,
          :running,
          nil
        )
      end,
      on_subtask_started: fn subtask ->
        if subtask.worker_invocation_id do
          broadcast_stage_invocation(
            orchestrator.workspace_id,
            run.pipeline_id,
            run.id,
            subtask.position,
            subtask.worker_invocation_id
          )
        end
      end,
      on_subtask_result: fn subtask, result ->
        {status, output} = extract_subtask_outcome(result)

        update_orchestrated_stage(
          run_stages_by_position,
          run,
          subtask.position,
          status,
          output
        )
      end
    }

    case Manager.execute_plan(plan, manager_inv, manager_state) do
      {:ok, results} ->
        Logger.info("Orchestrated pipeline completed with #{length(results)} results")
        finalize_orchestrated(:completed, results, manager_inv, pipeline_invocation)

      {:error, {:subtasks_failed, results}} ->
        Logger.warning("Orchestrated pipeline had subtask failures")
        finalize_orchestrated(:failed, results, manager_inv, pipeline_invocation)

      {:error, reason} ->
        Logger.error("Orchestrated pipeline failed: #{inspect(reason)}")
        halt_pipeline(pipeline_invocation, nil, reason)
    end
  end

  defp finalize_orchestrated(status, results, manager_inv, pipeline_invocation) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    output_summary = format_pipeline_results(results)

    end_reason = if status == :completed, do: :completed, else: :failed

    {:ok, _} =
      Orchestration.update_invocation_status(manager_inv, status, %{
        end_reason: end_reason,
        output: %{"results" => output_summary},
        completed_at: now
      })

    {:ok, _} =
      Orchestration.update_invocation_status(pipeline_invocation, status, %{
        end_reason: end_reason,
        output: %{"results" => output_summary},
        completed_at: now
      })

    case status do
      :completed -> {:ok, output_summary}
      :failed -> {:error, {:subtasks_failed, output_summary}}
    end
  end

  defp create_orchestrated_run_stages(run, stages) do
    stages
    |> Enum.sort_by(& &1.position)
    |> Enum.reduce(%{}, fn stage, acc ->
      agent = Agents.get_agent_with_provider!(stage.agent_id)

      {:ok, run_stage} =
        Pipelines.create_run_stage(
          %{
            pipeline_run_id: run.id,
            agent_id: stage.agent_id,
            position: stage.position,
            status: :pending
          }
          |> Map.merge(Agent.inference_snapshot(agent))
        )

      broadcast_stage_status(
        run.workspace_id,
        run.pipeline_id,
        run.id,
        stage.position,
        :pending
      )

      Map.put(acc, stage.position, run_stage)
    end)
  end

  defp update_orchestrated_stage(stages_by_position, run, position, status, output) do
    case Map.get(stages_by_position, position) do
      nil ->
        :ok

      run_stage ->
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        output_str = stringify_stage_output(output)

        attrs =
          case status do
            :running ->
              %{status: :running, started_at: now}

            :completed ->
              %{status: :completed, output: output_str, completed_at: now}

            :failed ->
              %{status: :failed, error: output_str, completed_at: now}
          end

        case Pipelines.update_run_stage(run_stage, attrs) do
          {:ok, _} ->
            :ok

          {:error, changeset} ->
            Logger.warning(
              "Failed to update run stage #{run_stage.id} to #{status}: #{inspect(changeset.errors)}"
            )
        end

        broadcast_stage_status(
          run.workspace_id,
          run.pipeline_id,
          run.id,
          position,
          status
        )
    end
  end

  defp stringify_stage_output(nil), do: nil
  defp stringify_stage_output(output) when is_binary(output), do: output
  defp stringify_stage_output(output) when is_map(output), do: Jason.encode!(output)
  defp stringify_stage_output(output), do: inspect(output)

  defp extract_subtask_outcome({:ok, _id, :completed, output}), do: {:completed, output}
  defp extract_subtask_outcome({:ok, _id, :failed, reason}), do: {:failed, inspect(reason)}
  defp extract_subtask_outcome({:error, _id, reason}), do: {:failed, inspect(reason)}

  defp ensure_agent_links(orchestrator, stages) do
    scope = %{user: nil}
    existing_workers = Agents.list_linked_workers(scope, orchestrator.id)
    existing_ids = MapSet.new(existing_workers, & &1.id)

    stages
    |> Enum.map(& &1.agent_id)
    |> Enum.uniq()
    |> Enum.each(fn agent_id ->
      unless MapSet.member?(existing_ids, agent_id) do
        Agents.link_agents(scope, %{
          manager_id: orchestrator.id,
          worker_id: agent_id,
          pattern: :delegate
        })
      end
    end)
  end

  defp build_plan_from_stages(stages) do
    stages
    |> Enum.sort_by(& &1.position)
    |> Enum.map(fn stage ->
      deps = stage_dependencies(stage)

      %{
        "description" =>
          stage.instruction || "Pipeline stage #{stage.position}: #{stage.agent.name}",
        "worker_id" => stage.agent_id,
        "depends_on" => deps,
        "acceptance_criteria" => nil
      }
    end)
  end

  defp stage_dependencies(%{depends_on_positions: list}) when is_list(list) and list != [],
    do: list

  defp stage_dependencies(%{position: 0}), do: []
  defp stage_dependencies(%{position: pos}), do: [pos - 1]

  # -------------------------------------------------------------------
  # Shared helpers
  # -------------------------------------------------------------------

  defp emit_stage_event(pipeline_invocation, stage, agent, event_type, is_final) do
    {:ok, _} =
      Orchestration.add_event(%{
        invocation_id: pipeline_invocation.id,
        agent_id: agent.id,
        event_type: event_type,
        visibility: if(is_final, do: :public, else: :internal),
        summary: "Stage #{stage.position + 1}: #{agent.name} #{event_type}",
        payload: %{"position" => stage.position, "agent_name" => agent.name}
      })
  end

  defp halt_pipeline(pipeline_invocation, stage, reason) do
    output =
      if stage do
        %{"failed_stage" => stage.position, "error" => inspect(reason)}
      else
        %{"error" => inspect(reason)}
      end

    {:ok, _} =
      Orchestration.update_invocation_status(pipeline_invocation, :awaiting_user, %{
        output: output
      })

    {:error, {:pipeline_halted, stage && stage.position, reason}}
  end

  @doc """
  Resumes a halted pipeline from the stored position.
  """
  def resume(pipeline_invocation, input_override \\ nil) do
    position = pipeline_invocation.pipeline_stage_position || 0
    input = input_override || get_previous_output(pipeline_invocation)

    run(pipeline_invocation, pipeline_invocation.pipeline_id, input, start_position: position)
  end

  @doc """
  Cancels a pipeline, marking it and all downstream work as cancelled.
  """
  def cancel(pipeline_invocation) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Orchestration.update_invocation_status(pipeline_invocation, :cancelled, %{
      end_reason: :cancelled,
      completed_at: now
    })
  end

  defp get_previous_output(pipeline_invocation) do
    case pipeline_invocation.output do
      %{"result" => result} -> result
      _ -> ""
    end
  end

  # -------------------------------------------------------------------
  # PubSub broadcasts
  # -------------------------------------------------------------------

  defp broadcast_run_status(workspace_id, pipeline_id, run_id, status) do
    Events.publish(%PipelineRunStatus{
      workspace_id: workspace_id,
      pipeline_id: pipeline_id,
      run_id: run_id,
      status: status
    })
  end

  defp broadcast_stage_status(workspace_id, pipeline_id, run_id, position, status) do
    Events.publish(%PipelineStageStatus{
      workspace_id: workspace_id,
      pipeline_id: pipeline_id,
      run_id: run_id,
      position: position,
      status: status
    })
  end

  defp broadcast_stage_invocation(workspace_id, pipeline_id, run_id, position, invocation_id) do
    Events.publish(%PipelineStageInvocation{
      workspace_id: workspace_id,
      pipeline_id: pipeline_id,
      run_id: run_id,
      position: position,
      invocation_id: invocation_id
    })
  end
end
