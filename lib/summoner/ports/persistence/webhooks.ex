defmodule Summoner.Ports.Persistence.Webhooks do
  @moduledoc "Port for webhooks persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :webhooks],
             Summoner.Adapters.Persistence.Webhooks
           )

  defdelegate create_webhook(scope, attrs), to: @adapter
  defdelegate update_webhook(scope, webhook, attrs), to: @adapter
  defdelegate delete_webhook(scope, webhook), to: @adapter
  defdelegate get_webhook!(scope, workspace_id, id), to: @adapter
  defdelegate get_webhook(id), to: @adapter
  defdelegate list_webhooks(scope, workspace_id, opts), to: @adapter
  defdelegate list_webhooks_paginated(scope, workspace_id, opts), to: @adapter
  defdelegate increment_trigger_count(id), to: @adapter
end
