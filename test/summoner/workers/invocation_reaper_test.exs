defmodule Summoner.Workers.InvocationReaperTest do
  use Summoner.DataCase, async: true

  alias Summoner.Accounts
  alias Summoner.AccountsFixtures
  alias Summoner.Agents
  alias Summoner.Orchestration
  alias Summoner.Providers
  alias Summoner.Workers.InvocationReaper
  alias Summoner.Workspaces

  import Summoner.TenantsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    scope = Accounts.Scope.for_user(user)
    tenant = tenant_fixture(scope)
    {:ok, workspace} = Workspaces.create_workspace(scope, tenant.id, %{name: "Test WS"})

    {:ok, provider} =
      Providers.create_provider(scope, %{
        name: "Test Provider",
        kind: "ollama",
        api_format: :openai,
        type: :local,
        base_url: "http://localhost:11434",
        workspace_id: workspace.id
      })

    {:ok, agent} =
      Agents.create_agent(scope, %{
        name: "Test Agent",
        model: "llama3",
        role: :autonomous,
        workspace_id: workspace.id,
        provider_id: provider.id,
        total_timeout_s: 10
      })

    %{scope: scope, workspace: workspace, agent: agent}
  end

  test "reaps orphaned running invocations with no live server", %{
    scope: scope,
    workspace: ws,
    agent: fam
  } do
    {:ok, invocation} =
      Orchestration.create_invocation(scope, %{
        workspace_id: ws.id,
        agent_id: fam.id,
        conversation_id: nil,
        input: %{"text" => "hello"}
      })

    # Move to running
    {:ok, invocation} =
      Orchestration.update_invocation_status(invocation, :running, %{
        started_at: DateTime.utc_now()
      })

    assert invocation.status == :running

    # No GenServer is running for this agent, so it should be reaped
    assert :ok = InvocationReaper.perform(%Oban.Job{})

    reloaded = Orchestration.get_invocation_by_id(invocation.id)
    assert reloaded.status == :queued
  end

  test "reaps timed-out running invocations", %{
    scope: scope,
    workspace: ws,
    agent: fam
  } do
    {:ok, invocation} =
      Orchestration.create_invocation(scope, %{
        workspace_id: ws.id,
        agent_id: fam.id,
        conversation_id: nil,
        input: %{"text" => "hello"}
      })

    # Move to running with started_at in the past (exceeds 10s timeout)
    past = DateTime.add(DateTime.utc_now(), -60, :second)

    {:ok, invocation} =
      Orchestration.update_invocation_status(invocation, :running, %{
        started_at: past
      })

    assert :ok = InvocationReaper.perform(%Oban.Job{})

    reloaded = Orchestration.get_invocation_by_id(invocation.id)
    assert reloaded.status == :queued
  end

  test "does not reap queued or completed invocations", %{
    scope: scope,
    workspace: ws,
    agent: fam
  } do
    {:ok, invocation} =
      Orchestration.create_invocation(scope, %{
        workspace_id: ws.id,
        agent_id: fam.id,
        conversation_id: nil,
        input: %{"text" => "hello"}
      })

    assert invocation.status == :queued

    assert :ok = InvocationReaper.perform(%Oban.Job{})

    reloaded = Orchestration.get_invocation_by_id(invocation.id)
    assert reloaded.status == :queued
  end
end
