defmodule Summoner.Workers.PipelineRunnerJob do
  @moduledoc """
  Oban worker that executes a single pipeline run.

  Enqueued manually (via the UI "Run" button) or by the PipelineScheduler.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [keys: [:pipeline_id], states: [:available, :scheduled, :executing, :retryable]]

  alias Summoner.Orchestration
  alias Summoner.Orchestration.PipelineRunner
  alias Summoner.Pipelines

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "pipeline_id" => pipeline_id,
          "workspace_id" => workspace_id,
          "input" => input
        }
      }) do
    if Pipelines.has_active_run?(pipeline_id) do
      {:cancel, "Pipeline already has an active run"}
    else
      execute_pipeline(pipeline_id, workspace_id, input)
    end
  end

  defp execute_pipeline(pipeline_id, workspace_id, input) do
    pipeline = Pipelines.get_pipeline!(%{user: nil}, workspace_id, pipeline_id)

    agent_id =
      if pipeline.orchestrator_agent_id do
        pipeline.orchestrator_agent_id
      else
        case pipeline.stages do
          [first | _] -> first.agent_id
          [] -> nil
        end
      end

    if is_nil(agent_id) do
      {:error, "Pipeline has no stages or orchestrator"}
    else
      {:ok, invocation} =
        Orchestration.create_invocation(%{user: nil}, %{
          workspace_id: workspace_id,
          agent_id: agent_id,
          pipeline_id: pipeline_id,
          status: :queued,
          input: %{"message" => input}
        })

      case PipelineRunner.run(invocation, pipeline_id, input) do
        {:ok, _output} -> :ok
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end
end
