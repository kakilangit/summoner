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

  # Workspaces
  @callback list_workspaces() :: struct()
  @callback list_workspaces(keyword()) :: struct()
  @callback get_workspace!(String.t()) :: struct()
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
