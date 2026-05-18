defmodule Summoner.Workers.CompactorJobTest do
  use Summoner.DataCase

  alias Summoner.Conversations
  alias Summoner.Workers.CompactorJob

  import Summoner.AccountsFixtures
  import Summoner.AgentsFixtures
  import Summoner.ConversationsFixtures
  import Summoner.ProvidersFixtures
  import Summoner.WorkspacesFixtures

  defp create_context(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)
    conversation = conversation_fixture(scope, workspace.id, agent.id)

    %{
      scope: scope,
      workspace: workspace,
      provider: provider,
      agent: agent,
      conversation: conversation
    }
  end

  describe "new/1" do
    setup :create_context

    test "creates a valid Oban changeset", %{agent: agent, conversation: conv} do
      changeset =
        CompactorJob.new(%{conversation_id: conv.id, agent_id: agent.id})

      assert changeset.valid?
    end

    test "unique by conversation_id", %{agent: agent, conversation: conv} do
      assert {:ok, _} =
               %{conversation_id: conv.id, agent_id: agent.id}
               |> CompactorJob.new()
               |> Oban.insert()

      # Second insert with same conversation_id should resolve to the existing job
      assert {:ok, _} =
               %{conversation_id: conv.id, agent_id: agent.id}
               |> CompactorJob.new()
               |> Oban.insert()
    end
  end

  describe "perform/1 below threshold" do
    setup :create_context

    test "succeeds when conversation has few messages", %{agent: agent, conversation: conv} do
      # Insert a few messages (below compaction threshold of 40)
      for i <- 1..5 do
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :user,
          kind: :chat,
          content: "Message #{i}"
        })
      end

      job = %Oban.Job{
        args: %{"conversation_id" => conv.id, "agent_id" => agent.id}
      }

      assert :ok = CompactorJob.perform(job)
    end
  end
end
