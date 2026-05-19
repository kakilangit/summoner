defmodule Summoner.Adapters.Persistence.Pipelines do
  @moduledoc """
  The Pipelines context.

  Manages pipeline definitions (ordered sequences of agents).
  Pipeline execution is handled by `Summoner.Services.Orchestration.PipelineRunner`.
  """

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Conversations
  alias Summoner.Adapters.Persistence.Pagination
  alias Summoner.Adapters.Persistence.Workspaces
  alias Summoner.Domain.Schemas.Invocation
  alias Summoner.Domain.Schemas.{Pipeline, PipelineRun, PipelineRunStage, PipelineStage}
  alias Summoner.Repo
  alias Summoner.Services.Orchestration.Cancellation

  # -------------------------------------------------------------------
  # Pipelines
  # -------------------------------------------------------------------

  @doc """
  Creates a pipeline in a workspace.
  """
  def create_pipeline(%{user: _user}, attrs) do
    %Pipeline{}
    |> Pipeline.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists pipelines for a workspace.
  """
  def list_pipelines(%{user: _user}, workspace_id) do
    Pipeline
    |> Workspaces.where_workspace(workspace_id)
    |> order_by([p], asc: p.name)
    |> preload(:stages)
    |> Repo.all()
  end

  @doc """
  Lists pipelines for a workspace with pagination.
  """
  def list_pipelines_paginated(%{user: _user}, workspace_id, opts \\ []) do
    page =
      Pipeline
      |> Workspaces.where_workspace(workspace_id)
      |> Pagination.paginate(opts)

    %{page | entries: Repo.preload(page.entries, :stages)}
  end

  @doc """
  Lists all scheduled pipelines (across all workspaces).
  Used by the PipelineScheduler worker.
  """
  def list_scheduled_pipelines do
    Pipeline
    |> where([p], p.trigger_type == :scheduled)
    |> where([p], not is_nil(p.cron_expression))
    |> preload(stages: :agent)
    |> Repo.all()
  end

  @doc """
  Gets a pipeline by ID, scoped to a workspace.
  """
  def get_pipeline!(%{user: _user}, workspace_id, pipeline_id) do
    Pipeline
    |> Workspaces.where_workspace(workspace_id)
    |> Repo.get!(pipeline_id)
    |> Repo.preload(stages: [agent: [local_agent: :provider]])
  end

  @doc """
  Updates a pipeline.
  """
  def update_pipeline(%{user: _user}, %Pipeline{} = pipeline, attrs) do
    pipeline
    |> Pipeline.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a pipeline.
  """
  def delete_pipeline(%{user: _user}, %Pipeline{} = pipeline) do
    Repo.delete(pipeline)
  end

  @doc """
  Ensures a pipeline has a persistent conversation for cross-run context.

  Returns the conversation_id (existing or newly created).
  The pipeline must have at least one stage with a preloaded agent.
  """
  def ensure_conversation(%Pipeline{conversation_id: id}) when is_binary(id), do: {:ok, id}

  def ensure_conversation(%Pipeline{} = pipeline) do
    primary_agent_id =
      case pipeline.stages do
        [first | _] -> first.agent_id
        [] -> nil
      end

    if is_nil(primary_agent_id) do
      {:error, :no_stages}
    else
      case Conversations.create_system_conversation(%{
             workspace_id: pipeline.workspace_id,
             primary_agent_id: primary_agent_id,
             title: "Quest: #{pipeline.name}",
             kind: :pipeline
           }) do
        {:ok, conversation} ->
          {:ok, _} =
            pipeline
            |> Ecto.Changeset.change(conversation_id: conversation.id)
            |> Repo.update()

          {:ok, conversation.id}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # -------------------------------------------------------------------
  # Stages
  # -------------------------------------------------------------------

  @doc """
  Adds a stage to a pipeline at the given position.
  """
  def add_stage(%{user: _user}, attrs) do
    %PipelineStage{}
    |> PipelineStage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a stage (e.g. changing its instruction).
  """
  def update_stage(%{user: _user}, %PipelineStage{} = stage, attrs) do
    stage
    |> PipelineStage.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Removes a stage from a pipeline.
  """
  def remove_stage(%{user: _user}, %PipelineStage{} = stage) do
    Repo.delete(stage)
  end

  @doc """
  Lists stages for a pipeline, ordered by position.
  """
  def list_stages(pipeline_id) do
    PipelineStage
    |> where([s], s.pipeline_id == ^pipeline_id)
    |> order_by([s], asc: s.position)
    |> preload(:agent)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Pipeline Runs
  # -------------------------------------------------------------------

  @doc """
  Creates a pipeline run record.
  """
  def create_run(attrs) do
    %PipelineRun{}
    |> PipelineRun.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a pipeline run (status, output, error, completed_at).
  """
  def update_run(%PipelineRun{} = run, attrs) do
    run
    |> PipelineRun.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists runs for a pipeline, most recent first.
  """
  def list_runs(pipeline_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    PipelineRun
    |> where([r], r.pipeline_id == ^pipeline_id)
    |> order_by([r], desc: r.started_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists runs for a pipeline with pagination.
  """
  def list_runs_paginated(pipeline_id, opts \\ []) do
    PipelineRun
    |> where([r], r.pipeline_id == ^pipeline_id)
    |> order_by([r], desc: r.started_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a run by ID with stages preloaded.
  """
  def get_run!(run_id) do
    PipelineRun
    |> Repo.get!(run_id)
    |> Repo.preload(stages: :agent)
  end

  @doc """
  Creates a run stage record.
  """
  def create_run_stage(attrs) do
    %PipelineRunStage{}
    |> PipelineRunStage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a run stage (status, output, error, timing).
  """
  def update_run_stage(%PipelineRunStage{} = stage, attrs) do
    stage
    |> PipelineRunStage.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns the latest run for a pipeline (or nil).
  """
  def latest_run(pipeline_id) do
    PipelineRun
    |> where([r], r.pipeline_id == ^pipeline_id)
    |> order_by([r], desc: r.started_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Returns true if the pipeline has a running pipeline run.
  """
  def has_active_run?(pipeline_id) do
    PipelineRun
    |> where([r], r.pipeline_id == ^pipeline_id)
    |> where([r], r.status == :running)
    |> Repo.exists?()
  end

  @doc """
  Cancels a running pipeline run by ID.
  Updates the run and all running/pending stages to cancelled.
  Also cancels the underlying invocation tree.
  """
  def cancel_run(run_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    case Repo.get(PipelineRun, run_id) do
      nil ->
        {:error, :not_found}

      %PipelineRun{status: status} when status in [:completed, :failed, :cancelled] ->
        {:error, :already_terminal}

      %PipelineRun{} = run ->
        # Cancel all non-terminal stages
        PipelineRunStage
        |> where([s], s.pipeline_run_id == ^run.id)
        |> where([s], s.status in [:pending, :running])
        |> Repo.update_all(set: [status: :skipped, completed_at: now])

        # Cancel the invocation tree (find running invocation for this pipeline)
        cancel_pipeline_invocations(run.pipeline_id)

        update_run(run, %{status: :cancelled, completed_at: now})
    end
  end

  defp cancel_pipeline_invocations(pipeline_id) do
    Invocation
    |> where([i], i.pipeline_id == ^pipeline_id)
    |> where([i], i.status in [:queued, :running])
    |> select([i], i.id)
    |> Repo.all()
    |> Enum.each(&Cancellation.cancel_tree/1)
  end

  @doc """
  Deletes a terminal pipeline run and its stages.
  Only completed, failed, or cancelled runs can be deleted.
  """
  def delete_run(run_id) do
    case Repo.get(PipelineRun, run_id) do
      nil ->
        {:error, :not_found}

      %PipelineRun{status: status} = run when status in [:completed, :failed, :cancelled] ->
        Repo.delete(run)

      %PipelineRun{} ->
        {:error, :still_running}
    end
  end
end
