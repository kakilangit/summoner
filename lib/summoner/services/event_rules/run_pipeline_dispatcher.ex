defmodule Summoner.Services.EventRules.RunPipelineDispatcher do
  @moduledoc """
  Action dispatcher that starts a pipeline run when an event rule fires.
  """

  @behaviour Summoner.Services.EventRules.ActionDispatcher

  alias Summoner.Ports.Persistence.Pipelines
  alias Summoner.Ports.Workers
  alias Summoner.Services.EventRules.InvokeAgentDispatcher

  require Logger

  @impl true
  def dispatch(%{"pipeline_id" => pipeline_id} = action_config, event_data) do
    workspace_id = event_data["workspace_id"]
    input = build_input(action_config, event_data)

    scope = %{user: :system}

    try do
      pipeline = Pipelines.get_pipeline!(scope, workspace_id, pipeline_id)

      case Pipelines.create_run(%{
             pipeline_id: pipeline.id,
             status: :pending,
             input: input
           }) do
        {:ok, run} ->
          Workers.enqueue_pipeline_run(%{
            "pipeline_id" => pipeline.id,
            "run_id" => run.id,
            "input" => input
          })

          {:ok, %{pipeline_id: pipeline.id, run_id: run.id}}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      Ecto.NoResultsError -> {:error, :pipeline_not_found}
    end
  end

  def dispatch(_config, _event_data), do: {:error, :no_pipeline_specified}

  defp build_input(%{"input_template" => template}, event_data) when is_binary(template) do
    InvokeAgentDispatcher.interpolate(template, event_data)
  end

  defp build_input(_config, event_data) do
    "Event rule triggered.\n\n#{Jason.encode!(event_data, pretty: true)}"
  end
end
