defmodule Summoner.Ports.Persistence.Orchestration.Adapter do
  @moduledoc "Behaviour for orchestration persistence operations."

  # Invocations
  @callback create_invocation(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback get_invocation!(map(), String.t(), String.t()) :: struct()
  @callback list_invocations(map(), String.t()) :: [struct()]
  @callback list_invocations(map(), String.t(), keyword()) :: [struct()]
  @callback list_running_invocations(String.t()) :: [struct()]
  @callback last_invocation(String.t(), String.t()) :: struct() | nil
  @callback update_invocation_status(struct(), atom()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_invocation_status(struct(), atom(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_invocation_status_by_id(String.t(), atom(), map()) ::
              {non_neg_integer(), nil}

  # Steps
  @callback add_step(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_steps(String.t()) :: [struct()]

  # Events
  @callback add_event(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_events(String.t()) :: [struct()]
  @callback list_events(String.t(), keyword()) :: [struct()]

  # Subtasks
  @callback create_subtasks(struct(), [map()]) :: {:ok, [struct()]} | {:error, Ecto.Changeset.t()}
  @callback claim_subtask(String.t(), String.t(), String.t()) ::
              {:ok, struct()} | {:error, :already_claimed}
  @callback complete_subtask(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback fail_subtask(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback skip_subtask(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback start_subtask(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback requeue_subtask(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback ready_subtasks(String.t()) :: [struct()]
  @callback list_subtasks(String.t()) :: [struct()]
  @callback get_subtask(String.t()) :: struct() | nil

  # Internal API
  @callback get_invocation_by_id(String.t()) :: struct() | nil
  @callback dequeue_invocation(String.t()) :: struct() | nil
  @callback cancel_queued_invocations_for_conversation(String.t()) :: {non_neg_integer(), nil}
  @callback running_invocation_ids(String.t(), String.t()) :: [String.t()]
  @callback conversation_active?(String.t()) :: boolean()
  @callback active_child_invocation_ids(String.t()) :: [String.t()]
  @callback update_subtask_deps(struct(), [String.t()]) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
end
