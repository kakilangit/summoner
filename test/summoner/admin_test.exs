defmodule Summoner.Adapters.Persistence.AdminTest do
  use Summoner.DataCase, async: true

  alias Summoner.Adapters.Persistence.Accounts
  alias Summoner.Adapters.Persistence.Admin
  alias Summoner.Domain.Schemas.Scope
  alias Summoner.Domain.Schemas.User

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  describe "list_users/1" do
    test "returns paginated users ordered by email" do
      user_a = user_fixture(%{email: "alpha@example.com"})
      user_b = user_fixture(%{email: "beta@example.com"})

      page = Admin.list_users()
      emails = Enum.map(page.entries, & &1.email)

      assert user_a.email in emails
      assert user_b.email in emails
      assert emails == Enum.sort(emails)
    end

    test "respects pagination options" do
      for i <- 1..5, do: user_fixture(%{email: "user#{i}@example.com"})

      page = Admin.list_users(page: 1, per_page: 2)
      assert length(page.entries) == 2
      assert page.total_entries >= 5
    end
  end

  describe "get_user!/1" do
    test "returns user by ID" do
      user = user_fixture()
      assert Admin.get_user!(user.id).id == user.id
    end

    test "raises on invalid ID" do
      {:ok, fake_id} = Nulid.generate()

      assert_raise Ecto.NoResultsError, fn ->
        Admin.get_user!(fake_id)
      end
    end
  end

  describe "update_user_role/2" do
    test "promotes user to admin" do
      user = user_fixture()
      assert user.role == "user"

      {:ok, updated} = Admin.update_user_role(user, "admin")
      assert updated.role == "admin"
    end

    test "demotes admin to user" do
      user = user_fixture()
      {:ok, admin} = Admin.update_user_role(user, "admin")

      {:ok, demoted} = Admin.update_user_role(admin, "user")
      assert demoted.role == "user"
    end

    test "rejects invalid role" do
      user = user_fixture()

      assert_raise FunctionClauseError, fn ->
        Admin.update_user_role(user, "superadmin")
      end
    end
  end

  describe "disable_user/1 and enable_user/1" do
    test "disables a user" do
      user = user_fixture()
      assert is_nil(user.disabled_at)

      {:ok, disabled} = Admin.disable_user(user)
      refute is_nil(disabled.disabled_at)
    end

    test "enables a disabled user" do
      user = user_fixture()
      {:ok, disabled} = Admin.disable_user(user)

      {:ok, enabled} = Admin.enable_user(disabled)
      assert is_nil(enabled.disabled_at)
    end
  end

  describe "reset_user_password/1" do
    test "generates new password and returns it" do
      user = user_fixture()

      {:ok, {updated, password}} = Admin.reset_user_password(user)
      assert is_binary(password)
      assert String.length(password) >= 12
      assert User.valid_password?(updated, password)
    end
  end

  describe "workspace functions" do
    test "list_workspaces/1 returns paginated workspaces" do
      scope = user_scope_fixture()
      workspace = workspace_fixture(scope)

      page = Admin.list_workspaces()
      ids = Enum.map(page.entries, & &1.id)
      assert workspace.id in ids
    end

    test "member_count/1 returns count of members" do
      scope = user_scope_fixture()
      workspace = workspace_fixture(scope)

      assert Admin.member_count(workspace) == 1
    end

    test "delete_workspace/1 deletes workspace" do
      scope = user_scope_fixture()
      workspace = workspace_fixture(scope)

      assert {:ok, _} = Admin.delete_workspace(workspace)

      assert_raise Ecto.NoResultsError, fn ->
        Summoner.Repo.get!(Summoner.Domain.Schemas.Workspace, workspace.id)
      end
    end

    test "list_user_workspaces/1 returns user's memberships" do
      scope = user_scope_fixture()
      workspace = workspace_fixture(scope)

      memberships = Admin.list_user_workspaces(scope.user)
      assert length(memberships) == 1
      assert hd(memberships).workspace.id == workspace.id
    end

    test "workspace_count_for_user/1 returns count" do
      scope = user_scope_fixture()
      _workspace = workspace_fixture(scope)

      assert Admin.workspace_count_for_user(scope.user) == 1
    end
  end

  describe "system_stats/0" do
    test "returns counts" do
      stats = Admin.system_stats()

      assert is_integer(stats.user_count)
      assert is_integer(stats.workspace_count)
      assert is_integer(stats.agent_count)
      assert is_integer(stats.invocation_count)
    end
  end

  describe "Scope.admin?/1" do
    test "returns true for admin users" do
      user = user_fixture()
      {:ok, admin} = Admin.update_user_role(user, "admin")
      scope = Scope.for_user(admin)

      assert Scope.admin?(scope)
    end

    test "returns false for regular users" do
      scope = user_scope_fixture()
      refute Scope.admin?(scope)
    end

    test "returns false for nil scope" do
      refute Scope.admin?(nil)
    end
  end

  describe "disabled user login rejection" do
    test "get_user_by_email_and_password rejects disabled users" do
      user = user_fixture()
      user = set_password(user)
      {:ok, _disabled} = Admin.disable_user(user)

      assert is_nil(
               Accounts.get_user_by_email_and_password(
                 user.email,
                 valid_user_password()
               )
             )
    end
  end
end
