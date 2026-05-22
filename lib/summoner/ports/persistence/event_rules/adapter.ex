defmodule Summoner.Ports.Persistence.EventRules.Adapter do
  @moduledoc "Behaviour for event rules persistence operations."

  @callback create_event_rule(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_event_rule(map(), struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_event_rule(map(), struct()) :: {:ok, struct()} | {:error, term()}
  @callback get_event_rule!(map(), String.t(), String.t()) :: struct()
  @callback list_event_rules(map(), String.t(), keyword()) :: [struct()]
  @callback list_event_rules_paginated(map(), String.t(), keyword()) :: struct()
  @callback list_enabled_rules_for_event(String.t(), String.t()) :: [struct()]
  @callback record_fire(String.t()) :: :ok
  @callback create_execution(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_execution(struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_executions(String.t(), keyword()) :: [struct()]
  @callback list_executions_paginated(String.t(), keyword()) :: struct()
  @callback change_event_rule(struct(), map()) :: Ecto.Changeset.t()
  @callback count_fires_in_window(String.t(), DateTime.t()) :: non_neg_integer()
  @callback record_success(String.t()) :: :ok
  @callback record_failure(String.t()) :: non_neg_integer()
  @callback trip_circuit(String.t(), DateTime.t()) :: :ok
  @callback reset_circuit(String.t()) :: :ok
end
