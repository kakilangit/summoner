defmodule Summoner.Ports.Persistence.MediaProviders.Adapter do
  @moduledoc "Behaviour for media providers persistence operations."

  @callback list_media_providers(map(), String.t(), String.t()) :: [struct()]
  @callback get_media_provider!(map(), String.t(), String.t(), String.t()) :: struct()
  @callback get_media_provider!(String.t()) :: struct()
  @callback create_media_provider(map(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_media_provider(map(), struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_media_provider(map(), struct()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback change_media_provider(struct()) :: Ecto.Changeset.t()
  @callback change_media_provider(struct(), map()) :: Ecto.Changeset.t()
  @callback get_default_media_provider(String.t()) :: struct() | nil
  @callback get_default_media_provider(String.t(), atom()) :: struct() | nil
  @callback resolve_media_provider(struct()) :: struct() | nil
  @callback resolve_media_provider(struct(), atom()) :: struct() | nil

  # Tenant-scoped
  @callback list_tenant_media_providers(String.t()) :: [struct()]
  @callback get_tenant_media_provider!(String.t(), String.t()) :: struct()
end
