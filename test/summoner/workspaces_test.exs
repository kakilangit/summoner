defmodule Summoner.Adapters.Persistence.WorkspacesTest do
  use Summoner.DataCase

  alias Summoner.Adapters.Persistence.Workspaces
  alias Summoner.Domain.Schemas.Workspace
  alias Summoner.Domain.Schemas.WorkspaceMembership
  alias Summoner.Domain.Schemas.WorkspaceSettings

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.TenantsFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  defp create_scope(_context) do
    scope = user_scope_fixture()
    tenant = tenant_fixture(scope)
    %{scope: scope, tenant: tenant}
  end

  describe "create_workspace/3" do
    setup :create_scope

    test "creates workspace with admin membership and default settings", %{
      scope: scope,
      tenant: tenant
    } do
      assert {:ok, %Workspace{} = workspace} =
               Workspaces.create_workspace(scope, tenant.id, %{name: "My Workspace"})

      assert workspace.name == "My Workspace"
      assert workspace.settings.context_window_messages == 20
      assert is_nil(workspace.settings.token_quota_monthly)

      membership = Repo.get_by!(WorkspaceMembership, workspace_id: workspace.id)
      assert membership.user_id == scope.user.id
      assert membership.role == :admin
    end

    test "requires name", %{scope: scope, tenant: tenant} do
      assert {:error, %Ecto.Changeset{}} = Workspaces.create_workspace(scope, tenant.id, %{})
    end

    test "validates name length", %{scope: scope, tenant: tenant} do
      long_name = String.duplicate("a", 101)

      assert {:error, changeset} =
               Workspaces.create_workspace(scope, tenant.id, %{name: long_name})

      assert "should be at most 100 character(s)" in errors_on(changeset).name
    end

    test "enforces unique workspace names", %{scope: scope, tenant: tenant} do
      workspace_fixture(scope, %{name: "Duplicate"})

      assert {:error, changeset} =
               Workspaces.create_workspace(scope, tenant.id, %{name: "Duplicate"})

      assert "has already been taken" in errors_on(changeset).name
    end
  end

  describe "list_workspaces_for_user/1" do
    setup :create_scope

    test "returns workspaces the user belongs to", %{scope: scope} do
      workspace = workspace_fixture(scope)
      workspaces = Workspaces.list_workspaces_for_user(scope)
      assert [%Workspace{id: id}] = workspaces
      assert id == workspace.id
    end

    test "does not return workspaces the user does not belong to", %{scope: scope} do
      other_scope = user_scope_fixture()
      _other_workspace = workspace_fixture(other_scope)

      assert Workspaces.list_workspaces_for_user(scope) == []
    end

    test "preloads settings", %{scope: scope} do
      _workspace = workspace_fixture(scope)
      [workspace] = Workspaces.list_workspaces_for_user(scope)
      assert %WorkspaceSettings{} = workspace.settings
    end
  end

  describe "get_workspace!/2" do
    setup :create_scope

    test "returns workspace when user is a member", %{scope: scope} do
      workspace = workspace_fixture(scope)
      fetched = Workspaces.get_workspace!(scope, workspace.id)
      assert fetched.id == workspace.id
    end

    test "raises when user is not a member" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()
      workspace = workspace_fixture(scope_a)

      assert_raise Ecto.NoResultsError, fn ->
        Workspaces.get_workspace!(scope_b, workspace.id)
      end
    end

    test "preloads settings", %{scope: scope} do
      workspace = workspace_fixture(scope)
      fetched = Workspaces.get_workspace!(scope, workspace.id)
      assert %WorkspaceSettings{} = fetched.settings
    end
  end

  describe "add_member/4" do
    setup :create_scope

    test "adds a user to a workspace", %{scope: scope} do
      workspace = workspace_fixture(scope)
      new_user = user_fixture()

      assert {:ok, %WorkspaceMembership{} = membership} =
               Workspaces.add_member(scope, workspace.id, new_user.id)

      assert membership.role == :member
    end

    test "adds a user with a specific role", %{scope: scope} do
      workspace = workspace_fixture(scope)
      new_user = user_fixture()

      assert {:ok, membership} =
               Workspaces.add_member(scope, workspace.id, new_user.id, :admin)

      assert membership.role == :admin
    end

    test "prevents duplicate memberships", %{scope: scope} do
      workspace = workspace_fixture(scope)
      new_user = user_fixture()
      {:ok, _} = Workspaces.add_member(scope, workspace.id, new_user.id)

      assert {:error, changeset} = Workspaces.add_member(scope, workspace.id, new_user.id)
      assert "has already been taken" in errors_on(changeset).workspace_id
    end
  end

  describe "remove_member/3" do
    setup :create_scope

    test "removes a user from a workspace", %{scope: scope} do
      workspace = workspace_fixture(scope)
      new_user = user_fixture()
      {:ok, _} = Workspaces.add_member(scope, workspace.id, new_user.id)

      assert {:ok, %WorkspaceMembership{}} =
               Workspaces.remove_member(scope, workspace.id, new_user.id)

      refute Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: new_user.id
             )
    end

    test "returns error when membership does not exist", %{scope: scope} do
      workspace = workspace_fixture(scope)
      non_member = user_fixture()

      assert {:error, :not_found} =
               Workspaces.remove_member(scope, workspace.id, non_member.id)
    end
  end

  describe "update_member_role/4" do
    setup :create_scope

    test "updates a member's role", %{scope: scope} do
      workspace = workspace_fixture(scope)
      new_user = user_fixture()
      {:ok, _} = Workspaces.add_member(scope, workspace.id, new_user.id)

      assert {:ok, membership} =
               Workspaces.update_member_role(scope, workspace.id, new_user.id, :admin)

      assert membership.role == :admin
    end

    test "returns error when membership does not exist", %{scope: scope} do
      workspace = workspace_fixture(scope)
      non_member = user_fixture()

      assert {:error, :not_found} =
               Workspaces.update_member_role(scope, workspace.id, non_member.id, :admin)
    end
  end

  describe "where_workspace/2" do
    setup :create_scope

    test "scopes query by workspace_id", %{scope: scope} do
      workspace = workspace_fixture(scope)

      query = Workspaces.where_workspace(WorkspaceMembership, workspace.id)
      results = Repo.all(query)

      assert length(results) == 1
      assert hd(results).workspace_id == workspace.id
    end
  end

  describe "delete_workspace/2" do
    setup :create_scope

    test "deletes a workspace and cascades all resources", %{scope: scope} do
      workspace = workspace_fixture(scope)
      assert {:ok, _} = Workspaces.delete_workspace(scope, workspace)

      assert_raise Ecto.NoResultsError, fn ->
        Workspaces.get_workspace!(scope, workspace.id)
      end
    end

    test "removes memberships and settings on cascade", %{scope: scope} do
      workspace = workspace_fixture(scope)
      assert {:ok, _} = Workspaces.delete_workspace(scope, workspace)

      refute Repo.get_by(WorkspaceMembership, workspace_id: workspace.id)
      refute Repo.get_by(WorkspaceSettings, workspace_id: workspace.id)
    end
  end
end
