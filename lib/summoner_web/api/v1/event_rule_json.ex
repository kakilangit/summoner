defmodule SummonerWeb.API.V1.EventRuleJSON do
  @moduledoc "JSON rendering for event rules."

  import SummonerWeb.API.PaginationJSON

  def index(%{page: page}) do
    %{items: Enum.map(page.entries, &event_rule_data/1), meta: page_meta(page)}
  end

  def show(%{event_rule: event_rule}) do
    event_rule_data(event_rule)
  end

  def executions(%{page: page}) do
    %{items: Enum.map(page.entries, &execution_data/1), meta: page_meta(page)}
  end

  defp event_rule_data(r) do
    %{
      id: r.id,
      name: r.name,
      description: r.description,
      event_type: r.event_type,
      conditions: r.conditions,
      action_type: r.action_type,
      action_config: r.action_config,
      cooldown_s: r.cooldown_s,
      enabled: r.enabled,
      priority: r.priority,
      last_fired_at: r.last_fired_at,
      fire_count: r.fire_count,
      max_fires_per_hour: r.max_fires_per_hour,
      consecutive_failures: r.consecutive_failures,
      disabled_until: r.disabled_until,
      workspace_id: r.workspace_id,
      inserted_at: r.inserted_at,
      updated_at: r.updated_at
    }
  end

  defp execution_data(e) do
    %{
      id: e.id,
      status: e.status,
      event_snapshot: e.event_snapshot,
      action_result: e.action_result,
      latency_ms: e.latency_ms,
      error_reason: e.error_reason,
      event_rule_id: e.event_rule_id,
      inserted_at: e.inserted_at
    }
  end
end
