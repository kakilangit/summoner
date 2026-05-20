defmodule Summoner.Ports.Persistence.Ledger.Adapter do
  @moduledoc "Behaviour for ledger persistence operations."

  # Quota & budget checks
  @callback check_workspace_quota(String.t()) ::
              :ok | {:error, :quota_exceeded, map()}
  @callback check_invocation_cap(String.t(), integer()) ::
              :ok | {:error, :token_limit_reached, map()}
  @callback check_agent_budget(String.t(), Decimal.t() | nil) ::
              :ok | {:error, :budget_exceeded, map()}
  @callback check_workspace_budget(String.t()) ::
              :ok | {:error, :budget_exceeded, map()}

  # Cost estimation
  @callback estimate_cost(String.t(), integer(), integer()) :: Decimal.t()

  # Usage queries
  @callback agent_total_cost(String.t()) :: Decimal.t()
  @callback rolling_30_day_cost(String.t()) :: Decimal.t()
  @callback estimate_tokens(term()) :: integer()
  @callback estimate_message_tokens(map()) :: integer()
  @callback estimate_context_tokens([map()]) :: integer()
  @callback rolling_30_day_usage(String.t()) :: integer()
  @callback invocation_token_usage(String.t()) :: integer()

  # Recording
  @callback record_usage(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}

  # Aggregations
  @callback usage_by_agent(String.t()) :: [map()]
  @callback usage_by_model(String.t()) :: [map()]
  @callback usage_by_provider(String.t()) :: [map()]
  @callback usage_for_agent(String.t()) :: map() | nil
  @callback usage_for_provider(String.t()) :: map() | nil
  @callback usage_by_model_for_provider(String.t()) :: [map()]
end
