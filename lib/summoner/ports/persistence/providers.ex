defmodule Summoner.Ports.Persistence.Providers do
  @moduledoc "Port for Providers persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :providers],
             Summoner.Adapters.Persistence.Providers
           )

  defdelegate create_provider(scope, attrs), to: @adapter
  defdelegate list_providers(scope, workspace_id, tenant_id), to: @adapter
  defdelegate list_providers_paginated(scope, workspace_id, tenant_id), to: @adapter
  defdelegate list_providers_paginated(scope, workspace_id, tenant_id, opts), to: @adapter
  defdelegate get_provider!(scope, workspace_id, tenant_id, provider_id), to: @adapter
  defdelegate update_provider(scope, provider, attrs), to: @adapter
  defdelegate delete_provider(scope, provider), to: @adapter
  defdelegate change_provider(provider), to: @adapter
  defdelegate change_provider(provider, attrs), to: @adapter

  # Internal API
  defdelegate list_all_providers(), to: @adapter
  defdelegate update_status(provider, status), to: @adapter
  defdelegate update_cached_models(provider, models), to: @adapter
  defdelegate available_models(scope, provider), to: @adapter
  defdelegate filter_models_by_capability(models, provider_kind, capability), to: @adapter

  # Copilot
  defdelegate start_copilot_connect(provider), to: @adapter

  # Tenant-scoped
  defdelegate list_tenant_providers(tenant_id), to: @adapter
  defdelegate list_tenant_providers_paginated(tenant_id), to: @adapter
  defdelegate list_tenant_providers_paginated(tenant_id, opts), to: @adapter
  defdelegate get_tenant_provider!(tenant_id, id), to: @adapter

  # Embedding
  defdelegate find_embedding_provider(workspace_id), to: @adapter
end
