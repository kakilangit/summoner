defmodule Summoner.Ports.Persistence.A2ATaskStore do
  @moduledoc "Port for A2A task store persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :a2a_task_store],
             Summoner.Adapters.Persistence.A2ATaskStore
           )

  defdelegate get(server_id, task_id), to: @adapter
  defdelegate put(server_id, task), to: @adapter
  defdelegate delete(server_id, task_id), to: @adapter
  defdelegate list(server_id, context_id), to: @adapter
  defdelegate list_all(server_id), to: @adapter
  defdelegate list_all(server_id, opts), to: @adapter
end
