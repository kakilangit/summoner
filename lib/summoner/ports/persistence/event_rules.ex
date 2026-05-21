defmodule Summoner.Ports.Persistence.EventRules do
  @moduledoc "Port for event rules persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :event_rules],
             Summoner.Adapters.Persistence.EventRules
           )

  defdelegate create_event_rule(scope, attrs), to: @adapter
  defdelegate update_event_rule(scope, event_rule, attrs), to: @adapter
  defdelegate delete_event_rule(scope, event_rule), to: @adapter
  defdelegate get_event_rule!(scope, workspace_id, id), to: @adapter
  defdelegate list_event_rules(scope, workspace_id, opts), to: @adapter
  defdelegate list_event_rules_paginated(scope, workspace_id, opts), to: @adapter
  defdelegate list_enabled_rules_for_event(workspace_id, event_type), to: @adapter
  defdelegate record_fire(id), to: @adapter
  defdelegate create_execution(attrs), to: @adapter
  defdelegate update_execution(execution, attrs), to: @adapter
  defdelegate list_executions(event_rule_id, opts), to: @adapter
  defdelegate list_executions_paginated(event_rule_id, opts), to: @adapter
end
