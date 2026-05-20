defmodule Summoner.Ports.Persistence.Workspaces.Adapter do
  @moduledoc "Behaviour for workspaces persistence operations."

  # Workspace directory
  @callback workspace_dir(String.t()) :: String.t()
  @callback open_workspace_dir(String.t()) :: :ok | {:error, String.t()}

  # Workspace CRUD
  @callback create_workspace(map(), String.t(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_workspaces_for_user(map()) :: [struct()]
  @callback list_workspaces_for_user_in_tenant_paginated(map(), String.t()) :: struct()
  @callback list_workspaces_for_user_in_tenant_paginated(map(), String.t(), keyword()) ::
              struct()
  @callback list_workspaces_for_user_paginated(map()) :: struct()
  @callback list_workspaces_for_user_paginated(map(), keyword()) :: struct()
  @callback get_workspace!(map(), String.t()) :: struct()

  # Membership management
  @callback list_members(map(), String.t()) :: [struct()]
  @callback get_membership(String.t(), String.t()) :: struct() | nil
  @callback add_member(map(), String.t(), String.t()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback add_member(map(), String.t(), String.t(), atom()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback remove_member(map(), String.t(), String.t()) ::
              {:ok, struct()} | {:error, :not_found}
  @callback update_member_role(map(), String.t(), String.t(), atom()) ::
              {:ok, struct()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}

  # Workspace updates
  @callback update_workspace(map(), struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_workspace(map(), struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}

  # Settings
  @callback update_settings(map(), struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback get_settings!(String.t()) :: struct()

  # Query helpers
  @callback where_workspace(Ecto.Queryable.t(), String.t()) :: Ecto.Query.t()
end
