defmodule Summoner.Ports.Persistence.Ledger do
  @moduledoc "Port for ledger persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :ledger],
             Summoner.Adapters.Persistence.Ledger
           )

  # Quota & budget checks
  defdelegate check_workspace_quota(workspace_id), to: @adapter
  defdelegate check_invocation_cap(invocation_id, max_tokens), to: @adapter
  defdelegate check_agent_budget(agent_id, budget_usd), to: @adapter
  defdelegate check_workspace_budget(workspace_id), to: @adapter

  # Cost estimation
  defdelegate estimate_cost(model, prompt_tokens, completion_tokens), to: @adapter

  # Usage queries
  defdelegate agent_total_cost(agent_id), to: @adapter
  defdelegate rolling_30_day_cost(workspace_id), to: @adapter
  defdelegate estimate_tokens(content), to: @adapter
  defdelegate estimate_message_tokens(msg), to: @adapter
  defdelegate estimate_context_tokens(messages), to: @adapter
  defdelegate rolling_30_day_usage(workspace_id), to: @adapter
  defdelegate invocation_token_usage(invocation_id), to: @adapter

  # Recording
  defdelegate record_usage(attrs), to: @adapter

  # Aggregations
  defdelegate usage_by_agent(workspace_id), to: @adapter
  defdelegate usage_by_model(workspace_id), to: @adapter
  defdelegate usage_by_provider(workspace_id), to: @adapter
  defdelegate usage_for_agent(agent_id), to: @adapter
  defdelegate usage_for_provider(provider_id), to: @adapter
  defdelegate usage_by_model_for_provider(provider_id), to: @adapter
end
