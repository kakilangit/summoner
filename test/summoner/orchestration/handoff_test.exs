defmodule Summoner.Orchestration.HandoffTest do
  use Summoner.DataCase

  alias Summoner.Conversations
  alias Summoner.Conversations.Content
  alias Summoner.Orchestration
  alias Summoner.Orchestration.Handoff

  import Summoner.AccountsFixtures
  import Summoner.AgentsFixtures
  import Summoner.ConversationsFixtures
  import Summoner.OrchestrationFixtures
  import Summoner.ProvidersFixtures
  import Summoner.WorkspacesFixtures

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    originator = agent_fixture(scope, workspace.id, provider.id, %{name: "Originator"})
    receiver = agent_fixture(scope, workspace.id, provider.id, %{name: "Receiver"})
    conversation = conversation_fixture(scope, workspace.id, originator.id)

    invocation =
      invocation_fixture(scope, workspace.id, originator.id, %{
        conversation_id: conversation.id,
        status: :running
      })

    %{
      scope: scope,
      workspace: workspace,
      originator: originator,
      receiver: receiver,
      conversation: conversation,
      invocation: invocation
    }
  end

  test "marks originator invocation as handed_off", ctx do
    start_supervised!(
      {Summoner.Agents.Server, [workspace_id: ctx.workspace.id, agent_id: ctx.receiver.id]},
      id: :receiver_server
    )

    assert {:ok, child_inv} = Handoff.execute(ctx.invocation, ctx.receiver.id)

    reloaded = Orchestration.get_invocation_by_id(ctx.invocation.id)
    assert reloaded.status == :handed_off
    assert reloaded.end_reason == :handed_off

    assert child_inv.agent_id == ctx.receiver.id
    assert child_inv.parent_invocation_id == ctx.invocation.id
    assert child_inv.conversation_id == ctx.conversation.id
  end

  test "writes public system message", ctx do
    start_supervised!(
      {Summoner.Agents.Server, [workspace_id: ctx.workspace.id, agent_id: ctx.receiver.id]},
      id: :receiver_server
    )

    assert {:ok, _} = Handoff.execute(ctx.invocation, ctx.receiver.id)

    messages = Conversations.list_messages(ctx.conversation.id, visibility: :public)
    system_msgs = Enum.filter(messages, &(&1.role == :system))
    assert system_msgs != []

    handoff_msg =
      Enum.find(system_msgs, fn msg ->
        text = Content.text_only(msg.content)
        String.contains?(text, "handed off")
      end)

    assert handoff_msg
    text = Content.text_only(handoff_msg.content)
    assert String.contains?(text, "Originator")
    assert String.contains?(text, "Receiver")
  end

  test "writes handoff_completed invocation event", ctx do
    start_supervised!(
      {Summoner.Agents.Server, [workspace_id: ctx.workspace.id, agent_id: ctx.receiver.id]},
      id: :receiver_server
    )

    assert {:ok, child_inv} = Handoff.execute(ctx.invocation, ctx.receiver.id)

    events = Orchestration.list_events(child_inv.id)
    assert length(events) == 1
    assert hd(events).event_type == :handoff_completed
  end

  test "updates conversation primary agent", ctx do
    start_supervised!(
      {Summoner.Agents.Server, [workspace_id: ctx.workspace.id, agent_id: ctx.receiver.id]},
      id: :receiver_server
    )

    assert {:ok, _} = Handoff.execute(ctx.invocation, ctx.receiver.id)

    conversation =
      Conversations.get_conversation!(
        %{user: ctx.scope.user},
        ctx.workspace.id,
        ctx.conversation.id
      )

    assert conversation.primary_agent_id == ctx.receiver.id
  end

  test "returns error for non-existent receiver", ctx do
    {:ok, fake_id} = Nulid.generate()
    assert {:error, :receiver_not_found} = Handoff.execute(ctx.invocation, fake_id)
  end
end
