defmodule Summoner.Adapters.MCP.Tools.RunPipeline do
  @moduledoc """
  Trigger a pipeline (Quest) run via MCP.

  Resolves the pipeline by ID, creates a synthetic invocation,
  and runs it via the PipelineRunner.
  """

  use Anubis.Server.Component, type: :tool

  alias Summoner.Domain.Schemas.Scope
  alias Summoner.Ports.Persistence.Orchestration
  alias Summoner.Ports.Persistence.Pipelines
  alias Summoner.Services.Orchestration.PipelineRunner

  alias Anubis.MCP.Error

  schema do
    field :pipeline_id, :string, required: true
    field :input, :string, required: true
  end

  @impl true
  def execute(args, frame) do
    workspace_id = frame.assigns[:workspace_id]
    scope = %Scope{user: nil}

    with {:ok, pipeline} <- resolve_pipeline(scope, workspace_id, args.pipeline_id),
         {:ok, invocation} <- create_invocation(scope, workspace_id, pipeline, args.input),
         {:ok, run} <- PipelineRunner.run(invocation, pipeline.id, args.input) do
      result = %{
        run_id: run.id,
        pipeline_id: pipeline.id,
        pipeline_name: pipeline.name,
        status: to_string(run.status),
        output: run.output
      }

      {:reply, Jason.encode!(result), frame}
    else
      {:error, reason} ->
        {:error, Error.protocol(:internal_error, %{message: inspect(reason)}), frame}
    end
  end

  defp resolve_pipeline(scope, workspace_id, pipeline_id) do
    pipeline = Pipelines.get_pipeline!(scope, workspace_id, pipeline_id)
    {:ok, pipeline}
  rescue
    Ecto.NoResultsError -> {:error, :pipeline_not_found}
  end

  defp create_invocation(scope, workspace_id, pipeline, input) do
    agent_id =
      pipeline.manager_agent_id ||
        pipeline.stages |> List.first() |> Map.get(:agent_id)

    Orchestration.create_invocation(scope, %{
      workspace_id: workspace_id,
      agent_id: agent_id,
      input: input,
      source: :mcp,
      status: :running
    })
  end
end
