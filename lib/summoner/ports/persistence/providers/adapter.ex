defmodule Summoner.Ports.Persistence.Providers.Adapter do
  @moduledoc "Behaviour for Providers persistence operations."

  alias Summoner.Domain.Schemas.Provider

  @callback create_provider(map(), map()) :: {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  @callback list_providers(map(), String.t(), String.t()) :: [Provider.t()]
  @callback list_providers_paginated(map(), String.t(), String.t()) :: struct()
  @callback list_providers_paginated(map(), String.t(), String.t(), keyword()) :: struct()
  @callback get_provider!(map(), String.t(), String.t(), String.t()) :: Provider.t()
  @callback update_provider(map(), Provider.t(), map()) ::
              {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  @callback delete_provider(map(), Provider.t()) ::
              {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  @callback change_provider(Provider.t()) :: Ecto.Changeset.t()
  @callback change_provider(Provider.t(), map()) :: Ecto.Changeset.t()

  # Internal API
  @callback list_all_providers() :: [Provider.t()]
  @callback update_status(Provider.t(), atom()) ::
              {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  @callback update_cached_models(Provider.t(), [String.t()]) ::
              {:ok, Provider.t()} | {:error, Ecto.Changeset.t()}
  @callback available_models(map(), Provider.t()) :: {:ok, [String.t()]}
  @callback filter_models_by_capability([String.t()], String.t(), atom()) :: [String.t()]

  # Copilot
  @callback start_copilot_connect(Provider.t()) :: {:ok, struct()} | {:error, term()}

  # Tenant-scoped
  @callback list_tenant_providers(String.t()) :: [Provider.t()]
  @callback list_tenant_providers_paginated(String.t()) :: struct()
  @callback list_tenant_providers_paginated(String.t(), keyword()) :: struct()
  @callback get_tenant_provider!(String.t(), String.t()) :: Provider.t()
end
