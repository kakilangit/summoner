defmodule Summoner.Domain.Policies.FailurePolicyTest do
  use Summoner.DataCase

  alias Summoner.Adapters.Persistence.Orchestration
  alias Summoner.Services.Orchestration.FailurePolicy

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.OrchestrationFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)

    %{scope: scope, workspace: workspace, agent: agent}
  end

  describe "can_retry?/1" do
    test "returns true when retry_count is 0", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)
      subtask = subtask_fixture(inv)

      assert FailurePolicy.can_retry?(subtask)
    end

    test "returns false when retry_count >= 1", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)
      subtask = subtask_fixture(inv)

      subtask = %{subtask | retry_count: 1}
      refute FailurePolicy.can_retry?(subtask)
    end
  end

  describe "apply_policy/3" do
    test ":skip marks subtask as skipped", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)
      subtask = subtask_fixture(inv)

      assert {:ok, :skipped} = FailurePolicy.apply_policy(:skip, inv, subtask)

      reloaded = Orchestration.get_subtask(subtask.id)
      assert reloaded.status == :skipped
    end

    test ":abort fails the invocation", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)
      subtask = subtask_fixture(inv)

      assert {:ok, :aborted} = FailurePolicy.apply_policy(:abort, inv, subtask)

      reloaded = Orchestration.get_invocation_by_id(inv.id)
      assert reloaded.status == :failed
      assert reloaded.end_reason == :failed
    end

    test ":escalate sets invocation to awaiting_user and writes event", ctx do
      inv = invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id)
      subtask = subtask_fixture(inv)

      assert {:ok, :escalated} = FailurePolicy.apply_policy(:escalate, inv, subtask)

      reloaded = Orchestration.get_invocation_by_id(inv.id)
      assert reloaded.status == :awaiting_user

      events = Orchestration.list_events(inv.id)
      assert length(events) == 1
      assert hd(events).event_type == :awaiting_user
    end
  end
end
