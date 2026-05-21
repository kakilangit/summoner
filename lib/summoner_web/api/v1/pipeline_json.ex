defmodule SummonerWeb.API.V1.PipelineJSON do
  @moduledoc "JSON rendering for pipelines and runs."

  import SummonerWeb.API.PaginationJSON

  def index(%{page: page}) do
    %{data: Enum.map(page.entries, &pipeline_data/1), meta: page_meta(page)}
  end

  def show(%{pipeline: pipeline}) do
    %{data: pipeline_data(pipeline)}
  end

  def runs(%{page: page}) do
    %{data: Enum.map(page.entries, &run_data/1), meta: page_meta(page)}
  end

  defp pipeline_data(p) do
    base = %{
      id: p.id,
      name: p.name,
      mode: p.mode,
      trigger_type: p.trigger_type,
      cron_expression: p.cron_expression,
      workspace_id: p.workspace_id,
      orchestrator_agent_id: p.orchestrator_agent_id,
      conversation_id: p.conversation_id,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at
    }

    case p do
      %{stages: stages} when is_list(stages) ->
        Map.put(base, :stages, Enum.map(stages, &stage_data/1))

      _ ->
        base
    end
  end

  defp stage_data(s) do
    %{
      id: s.id,
      position: s.position,
      instruction: s.instruction,
      depends_on_positions: s.depends_on_positions,
      skill: s.skill,
      agent_id: s.agent_id,
      pipeline_id: s.pipeline_id,
      inserted_at: s.inserted_at
    }
  end

  defp run_data(r) do
    %{
      id: r.id,
      status: r.status,
      input: r.input,
      output: r.output,
      error: r.error,
      started_at: r.started_at,
      completed_at: r.completed_at,
      pipeline_id: r.pipeline_id,
      workspace_id: r.workspace_id,
      inserted_at: r.inserted_at
    }
  end
end
