defmodule Summoner.EventsTest do
  use Summoner.DataCase

  alias Summoner.Events

  # -------------------------------------------------------------------
  # Subscribe + Publish round-trip
  # -------------------------------------------------------------------

  describe "subscribe/publish round-trip" do
    test "invocation started event is received" do
      event = %Events.InvocationStarted{
        workspace_id: "ws1",
        agent_id: "ag1",
        invocation_id: "inv1"
      }

      :ok = Events.subscribe({:invocation, "ws1", "inv1"})
      :ok = Events.publish(event)

      assert_receive %Events.InvocationStarted{invocation_id: "inv1"}
    end

    test "invocation completed event is received" do
      event = %Events.InvocationCompleted{
        workspace_id: "ws1",
        agent_id: "ag1",
        invocation_id: "inv1"
      }

      :ok = Events.subscribe({:invocation, "ws1", "inv1"})
      :ok = Events.publish(event)

      assert_receive %Events.InvocationCompleted{invocation_id: "inv1"}
    end

    test "invocation failed event is received" do
      event = %Events.InvocationFailed{
        workspace_id: "ws1",
        agent_id: "ag1",
        invocation_id: "inv1"
      }

      :ok = Events.subscribe({:invocation, "ws1", "inv1"})
      :ok = Events.publish(event)

      assert_receive %Events.InvocationFailed{invocation_id: "inv1"}
    end

    test "content token event is received on agent topic" do
      event = %Events.ContentToken{
        workspace_id: "ws1",
        agent_id: "ag1",
        invocation_id: "inv1",
        token: "Hello"
      }

      :ok = Events.subscribe({:agent, "ws1", "ag1"})
      :ok = Events.publish(event)

      assert_receive %Events.ContentToken{token: "Hello"}
    end

    test "escalation event is received" do
      event = %Events.Escalation{
        workspace_id: "ws1",
        invocation_id: "inv1",
        reason: "need human review"
      }

      :ok = Events.subscribe({:escalations, "ws1"})
      :ok = Events.publish(event)

      assert_receive %Events.Escalation{reason: "need human review"}
    end

    test "invocation event is received" do
      inner = %{event_type: :tool_started, summary: "Calling foo"}

      event = %Events.InvocationEvent{
        workspace_id: "ws1",
        agent_id: "ag1",
        invocation_id: "inv1",
        event: inner
      }

      :ok = Events.subscribe({:invocation_events, "ws1", "inv1"})
      :ok = Events.publish(event)

      assert_receive %Events.InvocationEvent{event: ^inner}
    end

    test "unsubscribed process does not receive messages" do
      :ok = Events.subscribe({:invocation, "ws1", "other"})

      event = %Events.InvocationStarted{
        workspace_id: "ws1",
        agent_id: "ag1",
        invocation_id: "inv1"
      }

      :ok = Events.publish(event)

      refute_receive %Events.InvocationStarted{}, 50
    end

    test "invocation events fan out to agent topic" do
      event = %Events.InvocationStarted{
        workspace_id: "ws1",
        agent_id: "ag1",
        invocation_id: "inv1"
      }

      :ok = Events.subscribe({:agent, "ws1", "ag1"})
      :ok = Events.publish(event)

      assert_receive %Events.InvocationStarted{invocation_id: "inv1"}
    end
  end

  # -------------------------------------------------------------------
  # Integration: Orchestration publishes domain events
  # -------------------------------------------------------------------

  describe "orchestration integration" do
    import Summoner.AccountsFixtures
    import Summoner.WorkspacesFixtures
    import Summoner.ProvidersFixtures
    import Summoner.AgentsFixtures
    import Summoner.ConversationsFixtures

    alias Summoner.Orchestration

    setup do
      scope = user_scope_fixture()
      workspace = workspace_fixture(scope)
      provider = provider_fixture(scope, workspace.id)
      agent = agent_fixture(scope, workspace.id, provider.id)
      conversation = conversation_fixture(scope, workspace.id, agent.id)

      {:ok, invocation} =
        Orchestration.create_invocation(scope, %{
          workspace_id: workspace.id,
          agent_id: agent.id,
          conversation_id: conversation.id,
          status: :queued,
          input: %{"message" => "test"}
        })

      %{
        scope: scope,
        workspace: workspace,
        agent: agent,
        invocation: invocation
      }
    end

    test "update_invocation_status broadcasts InvocationStarted", %{
      workspace: ws,
      invocation: inv
    } do
      :ok = Events.subscribe({:invocation, ws.id, inv.id})

      {:ok, _} = Orchestration.update_invocation_status(inv, :running)

      assert_receive %Events.InvocationStarted{invocation_id: invocation_id}
      assert invocation_id == inv.id
    end

    test "add_step persists without broadcasting", %{
      invocation: inv,
      workspace: ws
    } do
      :ok = Events.subscribe({:invocation, ws.id, inv.id})

      {:ok, step} =
        Orchestration.add_step(%{
          invocation_id: inv.id,
          workspace_id: ws.id,
          step_number: 1,
          reasoning: "thinking",
          status: :ok
        })

      assert step.step_number == 1
      refute_receive %Events.InvocationStarted{}, 50
    end

    test "add_event broadcasts InvocationEvent", %{
      workspace: ws,
      agent: agent,
      invocation: inv
    } do
      :ok = Events.subscribe({:invocation_events, ws.id, inv.id})

      {:ok, event} =
        Orchestration.add_event(%{
          invocation_id: inv.id,
          workspace_id: ws.id,
          agent_id: agent.id,
          event_type: :tool_started,
          summary: "Calling read_file"
        })

      assert_receive %Events.InvocationEvent{event: ^event}
    end

    test "add_step does not broadcast without workspace_id", %{
      workspace: ws,
      invocation: inv
    } do
      :ok = Events.subscribe({:invocation, ws.id, inv.id})

      {:ok, _step} =
        Orchestration.add_step(%{
          invocation_id: inv.id,
          step_number: 1,
          reasoning: "thinking",
          status: :ok
        })

      refute_receive %Events.InvocationStarted{}, 50
    end
  end
end
