defmodule Summoner.Ports.Persistence.Secrets do
  @moduledoc "Port for secrets persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :secrets],
             Summoner.Adapters.Persistence.Secrets
           )

  # CRUD
  defdelegate create_secret(scope, attrs), to: @adapter
  defdelegate list_secrets(scope, workspace_id, tenant_id), to: @adapter
  defdelegate list_secrets_paginated(scope, workspace_id, tenant_id), to: @adapter
  defdelegate list_secrets_paginated(scope, workspace_id, tenant_id, opts), to: @adapter
  defdelegate get_secret!(scope, workspace_id, tenant_id, secret_id), to: @adapter
  defdelegate update_secret(scope, secret, attrs), to: @adapter
  defdelegate delete_secret(scope, secret), to: @adapter

  # Resolution
  defdelegate resolve(workspace_id, tenant_id, env_map), to: @adapter
  defdelegate resolve_value(workspace_id, tenant_id, value), to: @adapter

  # Tenant-scoped
  defdelegate list_tenant_secrets(tenant_id), to: @adapter
  defdelegate list_tenant_secrets_paginated(tenant_id), to: @adapter
  defdelegate list_tenant_secrets_paginated(tenant_id, opts), to: @adapter
  defdelegate get_tenant_secret!(tenant_id, id), to: @adapter

  # Internal API
  defdelegate get_secret_by_id(secret_id), to: @adapter
end
