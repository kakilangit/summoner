defmodule Summoner.Ports.Persistence.Approvals do
  @moduledoc "Port for approvals persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :approvals],
             Summoner.Adapters.Persistence.Approvals
           )

  # Rules
  defdelegate create_rule(scope, attrs), to: @adapter
  defdelegate list_rules(scope, workspace_id), to: @adapter
  defdelegate list_rules_paginated(scope, workspace_id), to: @adapter
  defdelegate list_rules_paginated(scope, workspace_id, opts), to: @adapter
  defdelegate get_rule!(scope, workspace_id, rule_id), to: @adapter
  defdelegate update_rule(scope, rule, attrs), to: @adapter
  defdelegate delete_rule(scope, rule), to: @adapter
  defdelegate change_rule(rule), to: @adapter
  defdelegate change_rule(rule, attrs), to: @adapter
  defdelegate list_enabled_rules(workspace_id), to: @adapter

  # Pending Approvals
  defdelegate create_pending(scope, attrs), to: @adapter
  defdelegate list_pending(scope, workspace_id), to: @adapter
  defdelegate list_pending_paginated(scope, workspace_id), to: @adapter
  defdelegate list_pending_paginated(scope, workspace_id, opts), to: @adapter
  defdelegate get_pending!(scope, workspace_id, approval_id), to: @adapter
  defdelegate decide(approval, decision, user_id, note \\ nil), to: @adapter
  defdelegate count_pending(workspace_id), to: @adapter
  defdelegate list_expired(cutoff), to: @adapter
end
