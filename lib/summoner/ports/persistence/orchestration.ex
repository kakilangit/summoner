defmodule Summoner.Ports.Persistence.Orchestration do
  @moduledoc "Port for orchestration persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :orchestration],
             Summoner.Adapters.Persistence.Orchestration
           )

  # Invocations
  defdelegate create_invocation(scope, attrs), to: @adapter
  defdelegate get_invocation!(scope, workspace_id, invocation_id), to: @adapter
  defdelegate list_invocations(scope, workspace_id), to: @adapter
  defdelegate list_invocations(scope, workspace_id, opts), to: @adapter
  defdelegate list_running_invocations(agent_id), to: @adapter
  defdelegate last_invocation(agent_id, conversation_id), to: @adapter
  defdelegate update_invocation_status(invocation, status), to: @adapter
  defdelegate update_invocation_status(invocation, status, attrs), to: @adapter
  defdelegate update_invocation_status_by_id(invocation_id, status, attrs), to: @adapter

  # Steps
  defdelegate add_step(attrs), to: @adapter
  defdelegate list_steps(invocation_id), to: @adapter
  defdelegate list_steps_paginated(invocation_id, opts \\ []), to: @adapter

  # Events
  defdelegate add_event(attrs), to: @adapter
  defdelegate list_events(invocation_id), to: @adapter
  defdelegate list_events(invocation_id, opts), to: @adapter
  defdelegate list_events_paginated(invocation_id, opts \\ []), to: @adapter

  # Subtasks
  defdelegate create_subtasks(invocation, subtask_attrs_list), to: @adapter
  defdelegate claim_subtask(subtask_id, agent_id, worker_invocation_id), to: @adapter
  defdelegate complete_subtask(subtask), to: @adapter
  defdelegate fail_subtask(subtask), to: @adapter
  defdelegate skip_subtask(subtask), to: @adapter
  defdelegate start_subtask(subtask), to: @adapter
  defdelegate requeue_subtask(subtask), to: @adapter
  defdelegate ready_subtasks(invocation_id), to: @adapter
  defdelegate list_subtasks(invocation_id), to: @adapter
  defdelegate get_subtask(subtask_id), to: @adapter

  # Internal API
  defdelegate get_invocation_by_id(invocation_id), to: @adapter
  defdelegate dequeue_invocation(agent_id), to: @adapter
  defdelegate cancel_queued_invocations_for_conversation(conversation_id), to: @adapter
  defdelegate running_invocation_ids(agent_id, conversation_id), to: @adapter
  defdelegate conversation_active?(conversation_id), to: @adapter
  defdelegate active_child_invocation_ids(parent_invocation_id), to: @adapter
  defdelegate update_subtask_deps(subtask, deps), to: @adapter
end
