defmodule Summoner.Ports.Persistence.Tenants.Adapter do
  @moduledoc "Behaviour for tenants persistence operations."

  # Tenant CRUD
  @callback create_tenant(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_tenants_for_user(map()) :: [struct()]
  @callback get_tenant!(String.t()) :: struct()
  @callback get_tenant_by_name(String.t()) :: struct() | nil
  @callback update_tenant(struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_tenant(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback default_tenant_for_user(map()) :: struct() | nil

  # Membership management
  @callback get_membership(String.t(), String.t()) :: struct() | nil
  @callback list_members(String.t()) :: [struct()]
  @callback add_member(String.t(), String.t()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback add_member(String.t(), String.t(), atom()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback remove_member(String.t(), String.t()) ::
              {:ok, struct()} | {:error, :not_found}
  @callback update_member_role(String.t(), String.t(), atom()) ::
              {:ok, struct()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}

  # Settings
  @callback update_settings(struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
end
