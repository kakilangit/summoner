defmodule Summoner.Workspaces.PolicyTest do
  use ExUnit.Case, async: true

  alias Summoner.Workspaces.Policy
  alias Summoner.Workspaces.WorkspaceMembership

  describe "can?/2" do
    test "admin can do everything" do
      membership = %WorkspaceMembership{role: :admin}

      assert Policy.can?(membership, :manage_workspace)
      assert Policy.can?(membership, :manage_members)
      assert Policy.can?(membership, :delete_workspace)
      assert Policy.can?(membership, :configure)
      assert Policy.can?(membership, :operate)
      assert Policy.can?(membership, :view)
    end

    test "member can operate and view but not configure or manage" do
      membership = %WorkspaceMembership{role: :member}

      refute Policy.can?(membership, :manage_workspace)
      refute Policy.can?(membership, :manage_members)
      refute Policy.can?(membership, :delete_workspace)
      refute Policy.can?(membership, :configure)
      assert Policy.can?(membership, :operate)
      assert Policy.can?(membership, :view)
    end

    test "viewer can only view" do
      membership = %WorkspaceMembership{role: :viewer}

      refute Policy.can?(membership, :manage_workspace)
      refute Policy.can?(membership, :manage_members)
      refute Policy.can?(membership, :configure)
      refute Policy.can?(membership, :operate)
      assert Policy.can?(membership, :view)
    end

    test "nil membership cannot do anything" do
      refute Policy.can?(nil, :view)
      refute Policy.can?(nil, :operate)
      refute Policy.can?(nil, :configure)
    end

    test "unknown action returns false" do
      membership = %WorkspaceMembership{role: :admin}
      refute Policy.can?(membership, :unknown_action)
    end
  end

  describe "authorize!/2" do
    test "returns :ok when authorized" do
      membership = %WorkspaceMembership{role: :admin}
      assert :ok = Policy.authorize!(membership, :configure)
    end

    test "raises UnauthorizedError when not authorized" do
      membership = %WorkspaceMembership{role: :viewer}

      assert_raise Summoner.Workspaces.UnauthorizedError, fn ->
        Policy.authorize!(membership, :configure)
      end
    end
  end
end
