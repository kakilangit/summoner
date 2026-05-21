defmodule Summoner.Services.EventRules do
  @moduledoc """
  Service layer for event rules (Omens).

  Handles CRUD, evaluation, and action dispatch for event rules.
  Pure domain logic (condition evaluation, cooldown) is delegated to
  domain policies. Side effects go through ports.
  """

  alias Summoner.Domain.Policies.ConditionEvaluator
  alias Summoner.Domain.Policies.CooldownPolicy
  alias Summoner.Ports.Persistence.EventRules, as: Persistence

  require Logger

  @dispatchers %{
    invoke_agent: Summoner.Services.EventRules.InvokeAgentDispatcher,
    run_pipeline: Summoner.Services.EventRules.RunPipelineDispatcher,
    call_webhook: Summoner.Services.EventRules.CallWebhookDispatcher,
    send_notification: Summoner.Services.EventRules.SendNotificationDispatcher
  }

  # -------------------------------------------------------------------
  # CRUD (delegated to persistence port)
  # -------------------------------------------------------------------

  def create_rule(scope, attrs), do: Persistence.create_event_rule(scope, attrs)
  def update_rule(scope, event_rule, attrs), do: Persistence.update_event_rule(scope, event_rule, attrs)
  def delete_rule(scope, event_rule), do: Persistence.delete_event_rule(scope, event_rule)
  def get_rule!(scope, workspace_id, id), do: Persistence.get_event_rule!(scope, workspace_id, id)
  def list_rules(scope, workspace_id, opts \\ []), do: Persistence.list_event_rules(scope, workspace_id, opts)

  def list_rules_paginated(scope, workspace_id, opts \\ []),
    do: Persistence.list_event_rules_paginated(scope, workspace_id, opts)

  def change_rule(event_rule, attrs \\ %{}),
    do: Persistence.change_event_rule(event_rule, attrs)

  def list_executions(event_rule_id, opts \\ []),
    do: Persistence.list_executions(event_rule_id, opts)

  def list_executions_paginated(event_rule_id, opts \\ []),
    do: Persistence.list_executions_paginated(event_rule_id, opts)

  def toggle_rule(scope, event_rule, enabled) do
    Persistence.update_event_rule(scope, event_rule, %{enabled: enabled})
  end

  # -------------------------------------------------------------------
  # Evaluation + Dispatch
  # -------------------------------------------------------------------

  @doc """
  Evaluates all enabled rules for a given workspace + event type against
  the event payload. Fires matching rules that are not in cooldown.

  Called by the EventRuleEvaluator worker when a domain event is received.
  """
  @spec evaluate_and_dispatch(String.t(), String.t(), map()) :: :ok
  def evaluate_and_dispatch(workspace_id, event_type, event_data) do
    rules = Persistence.list_enabled_rules_for_event(workspace_id, event_type)

    for rule <- rules do
      evaluate_single_rule(rule, event_data)
    end

    :ok
  end

  @doc """
  Dry-run evaluation: checks if conditions match without dispatching.
  Useful for testing rules in the UI/API.
  """
  @spec test_rule(map(), map()) :: {:ok, boolean()} | {:error, term()}
  def test_rule(conditions, event_data) do
    {:ok, ConditionEvaluator.evaluate(conditions, event_data)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp evaluate_single_rule(rule, event_data) do
    start_time = System.monotonic_time(:millisecond)

    cond do
      CooldownPolicy.within_cooldown?(rule.last_fired_at, rule.cooldown_s) ->
        :cooldown

      not ConditionEvaluator.evaluate(rule.conditions, event_data) ->
        :no_match

      true ->
        fire_rule(rule, event_data, start_time)
    end
  end

  defp fire_rule(rule, event_data, start_time) do
    # Record the fire immediately
    Persistence.record_fire(rule.id)

    # Create execution record
    {:ok, execution} =
      Persistence.create_execution(%{
        event_rule_id: rule.id,
        status: :fired,
        event_snapshot: event_data
      })

    # Dispatch the action
    dispatcher = Map.fetch!(@dispatchers, rule.action_type)

    case dispatcher.dispatch(rule.action_config, event_data) do
      {:ok, result} ->
        latency = System.monotonic_time(:millisecond) - start_time

        Persistence.update_execution(execution, %{
          status: :succeeded,
          action_result: normalize_result(result),
          latency_ms: latency
        })

        Logger.info("Event rule '#{rule.name}' fired successfully (#{latency}ms)")

      {:error, reason} ->
        latency = System.monotonic_time(:millisecond) - start_time

        Persistence.update_execution(execution, %{
          status: :failed,
          error_reason: to_string(reason),
          latency_ms: latency
        })

        Logger.warning("Event rule '#{rule.name}' failed: #{inspect(reason)}")
    end
  end

  defp normalize_result(result) when is_map(result) do
    result
    |> Jason.encode!()
    |> Jason.decode!()
  rescue
    _ -> %{"result" => inspect(result)}
  end

  defp normalize_result(result), do: %{"result" => inspect(result)}
end
