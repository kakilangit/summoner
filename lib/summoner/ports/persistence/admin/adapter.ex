defmodule Summoner.Ports.Persistence.Admin.Adapter do
  @moduledoc "Behaviour for admin persistence operations."

  # Root admin / SMTP
  @callback root_admin?(struct()) :: boolean()
  @callback root_admin?(term()) :: boolean()
  @callback smtp_configured?() :: boolean()

  # Users
  @callback create_user(map()) :: {:ok, struct()} | {:error, term()}
  @callback list_users() :: struct()
  @callback list_users(keyword()) :: struct()
  @callback get_user!(String.t()) :: struct()
  @callback update_user_role(struct(), String.t()) ::
              {:ok, struct()} | {:error, :root_admin_protected} | {:error, Ecto.Changeset.t()}
  @callback disable_user(struct()) ::
              {:ok, struct()} | {:error, :root_admin_protected} | {:error, Ecto.Changeset.t()}
  @callback enable_user(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback reset_user_password(struct()) ::
              {:ok, {struct(), String.t()}} | {:error, Ecto.Changeset.t()}
  @callback workspace_count_for_user(struct()) :: non_neg_integer()
  @callback list_user_workspaces(struct()) :: [struct()]
  @callback first_workspace_for_user(struct()) :: struct() | nil
  @callback add_user_to_workspace(struct(), String.t(), atom()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback remove_user_from_workspace(struct(), String.t()) ::
              {:ok, struct()} | {:error, term()}

  @callback list_user_tenants(struct()) :: [struct()]
  @callback first_tenant_for_user(struct()) :: struct() | nil
  @callback add_user_to_tenant(struct(), String.t(), atom()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback remove_user_from_tenant(struct(), String.t()) ::
              {:ok, struct()} | {:error, term()}

  # System permissions
  @callback grant_system_permission(struct(), atom()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback revoke_system_permission(struct(), atom()) ::
              {:ok, :revoked} | {:error, :not_found}
  @callback list_system_permissions(struct()) :: [atom()]
  @callback user_has_system_permission?(struct(), atom()) :: boolean()

  # Workspaces
  @callback list_workspaces() :: struct()
  @callback list_workspaces(keyword()) :: struct()
  @callback get_workspace!(String.t()) :: struct()
  @callback all_workspaces() :: [struct()]
  @callback member_count(struct()) :: non_neg_integer()
  @callback delete_workspace(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}

  # Tenants
  @callback list_tenants() :: struct()
  @callback list_tenants(keyword()) :: struct()
  @callback get_tenant!(String.t()) :: struct()
  @callback tenant_member_count(struct()) :: non_neg_integer()
  @callback tenant_workspace_count(struct()) :: non_neg_integer()
  @callback disable_tenant(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback enable_tenant(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_tenant(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}

  # System stats
  @callback system_stats() :: map()

  # Helpers
  @callback generate_password() :: String.t()
end
