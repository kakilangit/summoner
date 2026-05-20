defmodule Summoner.Ports.Workers do
  @moduledoc """
  Port for enqueueing background workers.

  Decouples job enqueueing from infrastructure (Oban). The
  configured adapter handles job creation and scheduling.
  """

  @adapter Application.compile_env(
             :summoner,
             :worker_adapter,
             Summoner.Adapters.Workers.ObanAdapter
           )

  @doc "Enqueue a media generation job."
  @spec enqueue_media_generation(map()) :: {:ok, term()} | {:error, term()}
  def enqueue_media_generation(args), do: @adapter.enqueue_media_generation(args)

  @doc "Enqueue a pipeline run job."
  @spec enqueue_pipeline_run(map()) :: {:ok, term()} | {:error, term()}
  def enqueue_pipeline_run(args), do: @adapter.enqueue_pipeline_run(args)

  @doc "Enqueue a conversation compaction job."
  @spec enqueue_compaction(map()) :: {:ok, term()} | {:error, term()}
  def enqueue_compaction(args), do: @adapter.enqueue_compaction(args)
end
