defmodule Summoner.Ports.Persistence.Secrets.Adapter do
  @moduledoc "Behaviour for secrets persistence operations."

  # CRUD
  @callback create_secret(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_secrets(map(), String.t(), String.t()) :: [struct()]
  @callback list_secrets_paginated(map(), String.t(), String.t()) :: struct()
  @callback list_secrets_paginated(map(), String.t(), String.t(), keyword()) :: struct()
  @callback get_secret!(map(), String.t(), String.t(), String.t()) :: struct()
  @callback update_secret(map(), struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_secret(map(), struct()) ::
              {:ok, struct()} | {:error, :in_use, String.t()}

  # Resolution
  @callback resolve(String.t(), String.t(), map() | nil) ::
              {:ok, map()} | {:error, {:missing_secrets, [String.t()]}}
  @callback resolve_value(String.t(), String.t(), String.t() | nil) ::
              {:ok, String.t() | nil} | {:error, {:missing_secret, String.t()}}

  # Tenant-scoped
  @callback list_tenant_secrets(String.t()) :: [struct()]
  @callback list_tenant_secrets_paginated(String.t()) :: struct()
  @callback list_tenant_secrets_paginated(String.t(), keyword()) :: struct()
  @callback get_tenant_secret!(String.t(), String.t()) :: struct()

  # Internal API
  @callback get_secret_by_id(String.t()) :: struct() | nil
end
