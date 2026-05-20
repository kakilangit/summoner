defmodule Summoner.Ports.Persistence.A2A do
  @moduledoc "Port for A2A persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :a2a],
             Summoner.Adapters.Persistence.A2A
           )

  # A2A Server (Herald) CRUD
  defdelegate list_servers(scope, workspace_id), to: @adapter
  defdelegate get_server!(scope, workspace_id, server_id), to: @adapter
  defdelegate get_server_by_agent_id(agent_id), to: @adapter
  defdelegate get_server_with_agent!(server_id), to: @adapter
  defdelegate get_enabled_server_by_agent_id!(agent_id), to: @adapter
  defdelegate create_server(scope, attrs), to: @adapter
  defdelegate create_server(attrs), to: @adapter
  defdelegate update_server(scope, server, attrs), to: @adapter
  defdelegate update_server(server, attrs), to: @adapter
  defdelegate delete_server(scope, server), to: @adapter
  defdelegate delete_server(server), to: @adapter
  defdelegate change_server(server), to: @adapter
  defdelegate change_server(server, attrs), to: @adapter

  # A2A Token CRUD
  defdelegate list_tokens(workspace_id), to: @adapter
  defdelegate create_token(attrs), to: @adapter
  defdelegate revoke_token(token), to: @adapter
  defdelegate verify_token(workspace_id, plaintext), to: @adapter

  # A2A Task CRUD
  defdelegate get_task(task_id), to: @adapter
  defdelegate create_task(attrs), to: @adapter
  defdelegate update_task(task, attrs), to: @adapter
  defdelegate list_tasks_by_context(context_id), to: @adapter
  defdelegate list_tasks_by_server(server_id), to: @adapter
  defdelegate list_tasks_by_server(server_id, opts), to: @adapter
  defdelegate get_task_conversation(server_id, context_id), to: @adapter

  # Base URL
  defdelegate base_url(server), to: @adapter
end
