defmodule Summoner.Ports.Persistence.Approvals.Adapter do
  @moduledoc "Behaviour for approvals persistence operations."

  # Rules
  @callback create_rule(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_rules(map(), String.t()) :: [struct()]
  @callback list_rules_paginated(map(), String.t()) :: struct()
  @callback list_rules_paginated(map(), String.t(), keyword()) :: struct()
  @callback get_rule!(map(), String.t(), String.t()) :: struct()
  @callback update_rule(map(), struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_rule(map(), struct()) :: {:ok, struct()} | {:error, term()}
  @callback change_rule(struct()) :: Ecto.Changeset.t()
  @callback change_rule(struct(), map()) :: Ecto.Changeset.t()
  @callback list_enabled_rules(String.t()) :: [struct()]

  # Pending Approvals
  @callback create_pending(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_pending(map(), String.t()) :: [struct()]
  @callback list_pending_paginated(map(), String.t()) :: struct()
  @callback list_pending_paginated(map(), String.t(), keyword()) :: struct()
  @callback get_pending!(map(), String.t(), String.t()) :: struct()
  @callback decide(struct(), String.t(), String.t() | nil, String.t() | nil) ::
              {:ok, struct()} | {:error, term()}
  @callback count_pending(String.t()) :: non_neg_integer()
  @callback list_expired(DateTime.t()) :: [struct()]
end
