defmodule Summoner.ConversationsFixtures do
  @moduledoc """
  Test helpers for creating conversation-related entities.
  """

  alias Summoner.Conversations

  def valid_conversation_attributes(workspace_id, agent_id, attrs \\ %{}) do
    Enum.into(attrs, %{
      workspace_id: workspace_id,
      primary_agent_id: agent_id,
      title: "Conversation #{System.unique_integer([:positive])}"
    })
  end

  def conversation_fixture(scope, workspace_id, agent_id, attrs \\ %{}) do
    {:ok, conversation} =
      workspace_id
      |> valid_conversation_attributes(agent_id, attrs)
      |> then(&Conversations.create_conversation(scope, &1))

    conversation
  end
end
