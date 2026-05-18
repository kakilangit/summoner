defmodule Summoner.BroadcastsTest do
  use Summoner.DataCase

  alias Summoner.Broadcasts

  # -------------------------------------------------------------------
  # Topic builders
  # -------------------------------------------------------------------

  describe "topic builders" do
    test "invocation_topic/2 builds scoped topic" do
      assert Broadcasts.invocation_topic("ws1", "inv1") == "invocation:ws1:inv1"
    end

    test "invocation_events_topic/2 builds scoped topic" do
      assert Broadcasts.invocation_events_topic("ws1", "inv1") ==
               "invocation_events:ws1:inv1"
    end

    test "agent_topic/2 builds scoped topic" do
      assert Broadcasts.agent_topic("ws1", "fam1") == "agent:ws1:fam1"
    end

    test "escalations_topic/1 builds workspace topic" do
      assert Broadcasts.escalations_topic("ws1") == "escalations:ws1"
    end
  end

  # -------------------------------------------------------------------
  # Subscribe + Broadcast round-trip
  # -------------------------------------------------------------------

  describe "subscribe/broadcast round-trip" do
    test "invocation status broadcast is received" do
      topic = Broadcasts.invocation_topic("ws1", "inv1")
      :ok = Broadcasts.subscribe(topic)
      :ok = Broadcasts.broadcast_invocation_status("ws1", "inv1", :running)

      assert_receive {:invocation_status, "inv1", :running}
    end

    test "invocation step broadcast is received" do
      topic = Broadcasts.invocation_topic("ws1", "inv1")
      :ok = Broadcasts.subscribe(topic)

      step = %{step_number: 1, reasoning: "thinking"}
      :ok = Broadcasts.broadcast_invocation_step("ws1", "inv1", step)

      assert_receive {:invocation_step, ^step}
    end

    test "invocation event broadcast is received" do
      topic = Broadcasts.invocation_events_topic("ws1", "inv1")
      :ok = Broadcasts.subscribe(topic)

      event = %{event_type: :tool_started, summary: "Calling foo"}
      :ok = Broadcasts.broadcast_invocation_event("ws1", "inv1", event)

      assert_receive {:invocation_event, ^event}
    end

    test "content token broadcast is received" do
      topic = Broadcasts.agent_topic("ws1", "fam1")
      :ok = Broadcasts.subscribe(topic)
      :ok = Broadcasts.broadcast_content_token("ws1", "fam1", "inv1", "Hello")

      assert_receive {:content_token, "inv1", "Hello"}
    end

    test "escalation broadcast is received" do
      topic = Broadcasts.escalations_topic("ws1")
      :ok = Broadcasts.subscribe(topic)
      :ok = Broadcasts.broadcast_escalation("ws1", "inv1", "need human review")

      assert_receive {:escalation, "inv1", "need human review"}
    end

    test "unsubscribed process does not receive messages" do
      # Subscribe to a different topic
      :ok = Broadcasts.subscribe(Broadcasts.invocation_topic("ws1", "other"))

      # Broadcast to a topic we are NOT subscribed to
      :ok = Broadcasts.broadcast_invocation_status("ws1", "inv1", :running)

      refute_receive {:invocation_status, _, _}, 50
    end
  end

  # -------------------------------------------------------------------
  # Integration: Orchestration broadcasts on persistence
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

    test "update_invocation_status broadcasts status change", %{
      workspace: ws,
      invocation: inv
    } do
      topic = Broadcasts.invocation_topic(ws.id, inv.id)
      :ok = Broadcasts.subscribe(topic)

      {:ok, _} = Orchestration.update_invocation_status(inv, :running)

      assert_receive {:invocation_status, _, :running}
    end

    test "add_step broadcasts when workspace_id provided", %{
      workspace: ws,
      invocation: inv
    } do
      topic = Broadcasts.invocation_topic(ws.id, inv.id)
      :ok = Broadcasts.subscribe(topic)

      {:ok, step} =
        Orchestration.add_step(%{
          invocation_id: inv.id,
          workspace_id: ws.id,
          step_number: 1,
          reasoning: "thinking",
          status: :ok
        })

      assert_receive {:invocation_step, ^step}
    end

    test "add_event broadcasts when workspace_id provided", %{
      workspace: ws,
      agent: fam,
      invocation: inv
    } do
      topic = Broadcasts.invocation_events_topic(ws.id, inv.id)
      :ok = Broadcasts.subscribe(topic)

      {:ok, event} =
        Orchestration.add_event(%{
          invocation_id: inv.id,
          workspace_id: ws.id,
          agent_id: fam.id,
          event_type: :tool_started,
          summary: "Calling read_file"
        })

      assert_receive {:invocation_event, ^event}
    end

    test "add_step does not broadcast without workspace_id", %{
      workspace: ws,
      invocation: inv
    } do
      topic = Broadcasts.invocation_topic(ws.id, inv.id)
      :ok = Broadcasts.subscribe(topic)

      {:ok, _step} =
        Orchestration.add_step(%{
          invocation_id: inv.id,
          step_number: 1,
          reasoning: "thinking",
          status: :ok
        })

      refute_receive {:invocation_step, _}, 50
    end
  end
end
