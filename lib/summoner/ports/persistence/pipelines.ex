defmodule Summoner.Ports.Persistence.Pipelines do
  @moduledoc "Port for pipeline persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :pipelines],
             Summoner.Adapters.Persistence.Pipelines
           )

  # Pipelines
  defdelegate create_pipeline(scope, attrs), to: @adapter
  defdelegate list_pipelines(scope, workspace_id), to: @adapter
  defdelegate list_pipelines_paginated(scope, workspace_id), to: @adapter
  defdelegate list_pipelines_paginated(scope, workspace_id, opts), to: @adapter
  defdelegate list_scheduled_pipelines(), to: @adapter
  defdelegate get_pipeline!(scope, workspace_id, pipeline_id), to: @adapter
  defdelegate update_pipeline(scope, pipeline, attrs), to: @adapter
  defdelegate delete_pipeline(scope, pipeline), to: @adapter
  defdelegate ensure_conversation(pipeline), to: @adapter

  # Stages
  defdelegate add_stage(scope, attrs), to: @adapter
  defdelegate update_stage(scope, stage, attrs), to: @adapter
  defdelegate remove_stage(scope, stage), to: @adapter
  defdelegate list_stages(pipeline_id), to: @adapter

  # Pipeline Runs
  defdelegate create_run(attrs), to: @adapter
  defdelegate update_run(run, attrs), to: @adapter
  defdelegate list_runs(pipeline_id), to: @adapter
  defdelegate list_runs(pipeline_id, opts), to: @adapter
  defdelegate list_runs_paginated(pipeline_id), to: @adapter
  defdelegate list_runs_paginated(pipeline_id, opts), to: @adapter
  defdelegate get_run!(run_id), to: @adapter
  defdelegate create_run_stage(attrs), to: @adapter
  defdelegate update_run_stage(stage, attrs), to: @adapter
  defdelegate latest_run(pipeline_id), to: @adapter
  defdelegate has_active_run?(pipeline_id), to: @adapter
  defdelegate cancel_run(run_id), to: @adapter
  defdelegate delete_run(run_id), to: @adapter
end
