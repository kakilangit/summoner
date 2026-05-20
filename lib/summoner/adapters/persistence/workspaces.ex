defmodule Summoner.Adapters.Persistence.Workspaces do
  @moduledoc """
  The Workspaces context.

  Manages workspaces, memberships, and workspace-level settings.
  Workspaces are the primary isolation boundary — all resources
  (Agents, Skills, MCP servers, etc.) are scoped to a workspace.
  """

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Pagination
  alias Summoner.Domain.Schemas.{Workspace, WorkspaceMembership, WorkspaceSettings}
  alias Summoner.Repo

  # -------------------------------------------------------------------
  # Workspace directory
  # -------------------------------------------------------------------

  @doc """
  Returns the workspace-scoped data directory path.

  The directory is created if it does not exist.
  Defaults to `~/.summoner/workspaces/<workspace_id>`.
  """
  def workspace_dir(workspace_id) when is_binary(workspace_id) do
    data_dir = Application.get_env(:summoner, :data_dir, Path.expand("~/.summoner"))
    dir = Path.join([data_dir, "workspaces", workspace_id])
    File.mkdir_p!(dir)
    dir
  end

  @doc """
  Opens the workspace directory in the system file manager.

  Uses `open` on macOS, `xdg-open` on Linux, and `explorer` on Windows.
  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  def open_workspace_dir(workspace_id) when is_binary(workspace_id) do
    dir = workspace_dir(workspace_id)
    {cmd, args} = file_manager_cmd(dir)

    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, code} -> {:error, "#{cmd} exited with code #{code}: #{output}"}
    end
  rescue
    e in ErlangError -> {:error, Exception.message(e)}
  end

  defp file_manager_cmd(dir) do
    case :os.type() do
      {:unix, :darwin} -> {"open", [dir]}
      {:win32, _} -> {"explorer", [dir]}
      {:unix, _} -> {"xdg-open", [dir]}
    end
  end

  # -------------------------------------------------------------------
  # Workspace CRUD
  # -------------------------------------------------------------------

  @doc """
  Creates a workspace with the given user as owner.

  Atomically creates the workspace, an owner membership, and default settings.
  """
  def create_workspace(%{user: user}, tenant_id, attrs) when is_binary(tenant_id) do
    Repo.transact(fn ->
      with {:ok, workspace} <-
             Repo.insert(Workspace.changeset(%Workspace{tenant_id: tenant_id}, attrs)),
           {:ok, _membership} <-
             Repo.insert(
               WorkspaceMembership.changeset(%WorkspaceMembership{}, %{
                 workspace_id: workspace.id,
                 user_id: user.id,
                 role: :admin
               })
             ),
           {:ok, settings} <-
             Repo.insert(
               WorkspaceSettings.changeset(%WorkspaceSettings{}, %{
                 workspace_id: workspace.id
               })
             ) do
        workspace_dir(workspace.id)
        {:ok, %{workspace | settings: settings}}
      end
    end)
  end

  @doc """
  Lists all workspaces the given user is a member of.
  """
  def list_workspaces_for_user(%{user: user}) do
    Workspace
    |> join(:inner, [w], m in WorkspaceMembership, on: m.workspace_id == w.id)
    |> where([_w, m], m.user_id == ^user.id)
    |> order_by([w], asc: w.name)
    |> preload(:settings)
    |> Repo.all()
  end

  @doc """
  Lists workspaces for a user within a specific tenant, with pagination.
  """
  def list_workspaces_for_user_in_tenant_paginated(%{user: user}, tenant_id, opts \\ []) do
    page =
      Workspace
      |> join(:inner, [w], m in WorkspaceMembership, on: m.workspace_id == w.id)
      |> where([_w, m], m.user_id == ^user.id)
      |> where([w], w.tenant_id == ^tenant_id)
      |> Pagination.paginate(opts)

    %{page | entries: Repo.preload(page.entries, :settings)}
  end

  @doc """
  Lists workspaces for a user with pagination.
  """
  def list_workspaces_for_user_paginated(%{user: user}, opts \\ []) do
    page =
      Workspace
      |> join(:inner, [w], m in WorkspaceMembership, on: m.workspace_id == w.id)
      |> where([_w, m], m.user_id == ^user.id)
      |> Pagination.paginate(opts)

    %{page | entries: Repo.preload(page.entries, :settings)}
  end

  @doc """
  Gets a single workspace scoped to the given user's membership.

  Raises `Ecto.NoResultsError` if the workspace does not exist or
  the user is not a member.
  """
  def get_workspace!(%{user: user}, id) do
    Workspace
    |> join(:inner, [w], m in WorkspaceMembership, on: m.workspace_id == w.id)
    |> where([_w, m], m.user_id == ^user.id)
    |> where([w], w.id == ^id)
    |> preload(:settings)
    |> Repo.one!()
  end

  # -------------------------------------------------------------------
  # Membership management
  # -------------------------------------------------------------------

  @doc """
  Lists members of a workspace with their user data.
  """
  def list_members(%{user: _user}, workspace_id) do
    WorkspaceMembership
    |> where([m], m.workspace_id == ^workspace_id)
    |> preload(:user)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets the membership for a user in a workspace.

  Returns `nil` if not found.
  """
  def get_membership(workspace_id, user_id) do
    Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id)
  end

  @doc """
  Adds a user to a workspace with the given role.
  """
  def add_member(%{user: _user}, workspace_id, user_id, role \\ :member) do
    %WorkspaceMembership{}
    |> WorkspaceMembership.changeset(%{
      workspace_id: workspace_id,
      user_id: user_id,
      role: role
    })
    |> Repo.insert()
  end

  @doc """
  Removes a user from a workspace.

  Returns `{:ok, membership}` or `{:error, :not_found}`.
  """
  def remove_member(%{user: _user}, workspace_id, user_id) do
    case Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id) do
      nil -> {:error, :not_found}
      membership -> Repo.delete(membership)
    end
  end

  @doc """
  Updates a member's role in a workspace.

  Returns `{:ok, membership}` or `{:error, :not_found}`.
  """
  def update_member_role(%{user: _user}, workspace_id, user_id, role) do
    case Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      membership ->
        membership
        |> WorkspaceMembership.changeset(%{role: role})
        |> Repo.update()
    end
  end

  @doc """
  Updates a workspace.
  """
  def update_workspace(%{user: _user}, %Workspace{} = workspace, attrs) do
    workspace
    |> Workspace.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a workspace and all its resources (cascading).

  This is a destructive operation. All agents, providers, MCP servers,
  conversations, pipelines, parties, secrets, skills, memberships, and
  settings belonging to the workspace will be permanently removed.
  """
  def delete_workspace(%{user: _user}, %Workspace{} = workspace) do
    Repo.delete(workspace)
  end

  @doc """
  Updates workspace settings.
  """
  def update_settings(%{user: _user}, %Workspace{} = workspace, attrs) do
    workspace.settings
    |> WorkspaceSettings.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets workspace settings by workspace ID.

  Intended for infrastructure use (e.g. GenServer context assembly).
  """
  def get_settings!(workspace_id) do
    WorkspaceSettings
    |> where([s], s.workspace_id == ^workspace_id)
    |> Repo.one!()
  end

  # -------------------------------------------------------------------
  # Query helpers
  # -------------------------------------------------------------------

  @doc """
  Adds a `WHERE workspace_id = ?` clause to the given query.

  Intended for use by other contexts that need workspace-scoped queries.

  ## Example

      Agent
      |> Workspaces.where_workspace(workspace_id)
      |> Repo.all()
  """
  def where_workspace(query, workspace_id) do
    where(query, [q], q.workspace_id == ^workspace_id)
  end
end
