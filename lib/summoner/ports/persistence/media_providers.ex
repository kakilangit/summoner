defmodule Summoner.Ports.Persistence.MediaProviders do
  @moduledoc "Port for media providers persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :media_providers],
             Summoner.Adapters.Persistence.MediaProviders
           )

  defdelegate list_media_providers(scope, workspace_id, tenant_id), to: @adapter

  defdelegate list_media_providers_paginated(scope, workspace_id, tenant_id, opts \\ []),
    to: @adapter

  defdelegate get_media_provider!(scope, workspace_id, tenant_id, id), to: @adapter
  defdelegate get_media_provider!(id), to: @adapter
  defdelegate create_media_provider(scope, attrs), to: @adapter
  defdelegate update_media_provider(scope, provider, attrs), to: @adapter
  defdelegate delete_media_provider(scope, provider), to: @adapter
  defdelegate change_media_provider(provider), to: @adapter
  defdelegate change_media_provider(provider, attrs), to: @adapter
  defdelegate get_default_media_provider(workspace_id), to: @adapter
  defdelegate get_default_media_provider(workspace_id, type), to: @adapter
  defdelegate resolve_media_provider(agent), to: @adapter
  defdelegate resolve_media_provider(agent, type), to: @adapter

  # Tenant-scoped
  defdelegate list_tenant_media_providers(tenant_id), to: @adapter
  defdelegate get_tenant_media_provider!(tenant_id, id), to: @adapter
end
