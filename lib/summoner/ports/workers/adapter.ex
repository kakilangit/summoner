defmodule Summoner.Ports.Workers.Adapter do
  @moduledoc """
  Behaviour for worker adapters.

  Adapters translate high-level job-enqueueing calls into
  infrastructure-specific operations (e.g., Oban).
  """

  @callback enqueue_media_generation(args :: map()) :: {:ok, term()} | {:error, term()}
  @callback enqueue_pipeline_run(args :: map()) :: {:ok, term()} | {:error, term()}
  @callback enqueue_compaction(args :: map()) :: {:ok, term()} | {:error, term()}
end
