defmodule Summoner.Ports.Persistence.Pipelines.Adapter do
  @moduledoc "Behaviour for pipeline persistence operations."

  # Pipelines
  @callback create_pipeline(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_pipelines(map(), String.t()) :: [struct()]
  @callback list_pipelines_paginated(map(), String.t()) :: struct()
  @callback list_pipelines_paginated(map(), String.t(), keyword()) :: struct()
  @callback list_scheduled_pipelines() :: [struct()]
  @callback get_pipeline!(map(), String.t(), String.t()) :: struct()
  @callback update_pipeline(map(), struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_pipeline(map(), struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback ensure_conversation(struct()) :: {:ok, String.t()} | {:error, term()}

  # Stages
  @callback add_stage(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_stage(map(), struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback remove_stage(map(), struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_stages(String.t()) :: [struct()]

  # Pipeline Runs
  @callback create_run(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_run(struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_runs(String.t()) :: [struct()]
  @callback list_runs(String.t(), keyword()) :: [struct()]
  @callback list_runs_paginated(String.t()) :: struct()
  @callback list_runs_paginated(String.t(), keyword()) :: struct()
  @callback get_run!(String.t()) :: struct()
  @callback create_run_stage(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_run_stage(struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback latest_run(String.t()) :: struct() | nil
  @callback has_active_run?(String.t()) :: boolean()
  @callback cancel_run(String.t()) ::
              {:ok, struct()} | {:error, :not_found | :already_terminal}
  @callback delete_run(String.t()) ::
              {:ok, struct()} | {:error, :not_found | :still_running}
end
