defmodule Summoner.Domain.Policies.WorkspacePolicyTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Policies.WorkspacePolicy, as: Policy
  alias Summoner.Domain.Schemas.WorkspaceMembership

  describe "can?/2" do
    test "owner can do everything including delete" do
      membership = %WorkspaceMembership{role: :owner}

      assert Policy.can?(membership, :delete_workspace)
      assert Policy.can?(membership, :manage_workspace_settings)
      assert Policy.can?(membership, :manage_workspace_members)
      assert Policy.can?(membership, :create_agents)
      assert Policy.can?(membership, :invoke_agents)
      assert Policy.can?(membership, :view_artifacts)
    end

    test "admin can manage but not delete workspace" do
      membership = %WorkspaceMembership{role: :admin}

      refute Policy.can?(membership, :delete_workspace)
      assert Policy.can?(membership, :manage_workspace_settings)
      assert Policy.can?(membership, :manage_workspace_members)
      assert Policy.can?(membership, :create_agents)
      assert Policy.can?(membership, :invoke_agents)
      assert Policy.can?(membership, :view_artifacts)
    end

    test "member can create and invoke but not manage" do
      membership = %WorkspaceMembership{role: :member}

      refute Policy.can?(membership, :delete_workspace)
      refute Policy.can?(membership, :manage_workspace_settings)
      refute Policy.can?(membership, :manage_workspace_members)
      assert Policy.can?(membership, :create_agents)
      assert Policy.can?(membership, :invoke_agents)
      assert Policy.can?(membership, :view_artifacts)
    end

    test "viewer can only view" do
      membership = %WorkspaceMembership{role: :viewer}

      refute Policy.can?(membership, :delete_workspace)
      refute Policy.can?(membership, :manage_workspace_settings)
      refute Policy.can?(membership, :manage_workspace_members)
      refute Policy.can?(membership, :create_agents)
      refute Policy.can?(membership, :invoke_agents)
      assert Policy.can?(membership, :view_artifacts)
    end

    test "nil membership cannot do anything" do
      refute Policy.can?(nil, :view_artifacts)
      refute Policy.can?(nil, :invoke_agents)
      refute Policy.can?(nil, :manage_workspace_settings)
    end

    test "unknown action returns false" do
      membership = %WorkspaceMembership{role: :admin}
      refute Policy.can?(membership, :unknown_action)
    end
  end

  describe "authorize!/2" do
    test "returns :ok when authorized" do
      membership = %WorkspaceMembership{role: :admin}
      assert :ok = Policy.authorize!(membership, :manage_workspace_settings)
    end

    test "raises UnauthorizedError when not authorized" do
      membership = %WorkspaceMembership{role: :viewer}

      assert_raise Summoner.Domain.Policies.UnauthorizedError, fn ->
        Policy.authorize!(membership, :manage_workspace_settings)
      end
    end
  end
end
