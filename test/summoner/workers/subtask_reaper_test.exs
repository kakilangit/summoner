defmodule Summoner.Adapters.Workers.SubtaskReaperTest do
  use Summoner.DataCase, async: true

  alias Summoner.Adapters.Persistence.Orchestration
  alias Summoner.Adapters.Workers.SubtaskReaper
  alias Summoner.Repo

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

  test "requeues claimed subtask with no live worker", %{
    scope: scope,
    workspace: ws,
    agent: agent
  } do
    inv = invocation_fixture(scope, ws.id, agent.id)
    subtask = subtask_fixture(inv)

    # Claim the subtask
    worker_inv = invocation_fixture(scope, ws.id, agent.id)
    {:ok, claimed} = Orchestration.claim_subtask(subtask.id, agent.id, worker_inv.id)

    assert claimed.status == :running

    # No live GenServer for this agent — reaper should requeue
    assert :ok = SubtaskReaper.perform(%Oban.Job{})

    reloaded = Orchestration.get_subtask(subtask.id)
    assert reloaded.status == :pending
    assert reloaded.retry_count == 1
  end

  test "fails subtask when retry budget exhausted", %{scope: scope, workspace: ws, agent: agent} do
    inv = invocation_fixture(scope, ws.id, agent.id)
    subtask = subtask_fixture(inv)

    worker_inv = invocation_fixture(scope, ws.id, agent.id)
    {:ok, claimed} = Orchestration.claim_subtask(subtask.id, agent.id, worker_inv.id)

    # Set retry_count to max (1)
    claimed
    |> Ecto.Changeset.change(%{retry_count: 1})
    |> Repo.update!()

    assert :ok = SubtaskReaper.perform(%Oban.Job{})

    reloaded = Orchestration.get_subtask(subtask.id)
    assert reloaded.status == :failed
  end

  test "does not reap pending subtasks", %{scope: scope, workspace: ws, agent: agent} do
    inv = invocation_fixture(scope, ws.id, agent.id)
    _subtask = subtask_fixture(inv)

    assert :ok = SubtaskReaper.perform(%Oban.Job{})

    # Should still be pending
    [reloaded] = Orchestration.list_subtasks(inv.id)
    assert reloaded.status == :pending
  end
end
