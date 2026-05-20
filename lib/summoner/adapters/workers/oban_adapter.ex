defmodule Summoner.Adapters.Workers.ObanAdapter do
  @moduledoc """
  Oban-backed implementation of the `Workers` port.

  Delegates to the existing Oban worker modules for job creation
  and uses `Oban.insert/1` for enqueueing.
  """

  @behaviour Summoner.Ports.Workers.Adapter

  alias Summoner.Adapters.Workers.{CompactorJob, MediaGeneration, PipelineRunnerJob}

  @impl true
  def enqueue_media_generation(args) do
    args
    |> MediaGeneration.new()
    |> Oban.insert()
  end

  @impl true
  def enqueue_pipeline_run(args) do
    args
    |> PipelineRunnerJob.new()
    |> Oban.insert()
  end

  @impl true
  def enqueue_compaction(args) do
    args
    |> CompactorJob.new()
    |> Oban.insert()
  end
end
