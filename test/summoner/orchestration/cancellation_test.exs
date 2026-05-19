defmodule Summoner.Services.Orchestration.CancellationTest do
  use Summoner.DataCase

  alias Summoner.Adapters.Persistence.Orchestration
  alias Summoner.Services.Orchestration.Cancellation

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

  test "cancels a single invocation", ctx do
    inv =
      invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id, %{status: :running})

    assert {:ok, 1} = Cancellation.cancel_tree(inv.id)

    reloaded = Orchestration.get_invocation_by_id(inv.id)
    assert reloaded.status == :cancelled
    assert reloaded.end_reason == :cancelled
  end

  test "cascades cancellation to child invocations", ctx do
    parent =
      invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id, %{status: :running})

    child =
      invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id, %{
        status: :running,
        parent_invocation_id: parent.id,
        depth: 1
      })

    grandchild =
      invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id, %{
        status: :queued,
        parent_invocation_id: child.id,
        depth: 2
      })

    assert {:ok, 3} = Cancellation.cancel_tree(parent.id)

    assert Orchestration.get_invocation_by_id(parent.id).status == :cancelled
    assert Orchestration.get_invocation_by_id(child.id).status == :cancelled
    assert Orchestration.get_invocation_by_id(grandchild.id).status == :cancelled
  end

  test "skips already-completed descendants", ctx do
    parent =
      invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id, %{status: :running})

    _completed_child =
      invocation_fixture(ctx.scope, ctx.workspace.id, ctx.agent.id, %{
        status: :completed,
        parent_invocation_id: parent.id,
        depth: 1
      })

    # Only parent should be cancelled (completed child is skipped in traversal)
    assert {:ok, 1} = Cancellation.cancel_tree(parent.id)
  end

  test "returns error for non-existent invocation" do
    {:ok, fake_id} = Nulid.generate()
    assert {:error, :not_found} = Cancellation.cancel_tree(fake_id)
  end
end
