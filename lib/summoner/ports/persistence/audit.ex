defmodule Summoner.Ports.Persistence.Audit do
  @moduledoc "Port for audit persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :audit],
             Summoner.Adapters.Persistence.Audit
           )

  defdelegate log(attrs), to: @adapter
  defdelegate list_logs(workspace_id), to: @adapter
  defdelegate list_logs(workspace_id, opts), to: @adapter
end
