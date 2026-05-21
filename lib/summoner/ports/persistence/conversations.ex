defmodule Summoner.Ports.Persistence.Conversations do
  @moduledoc "Port for conversation persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :conversations],
             Summoner.Adapters.Persistence.Conversations
           )

  # Conversations
  defdelegate create_conversation(scope, attrs), to: @adapter
  defdelegate create_system_conversation(attrs), to: @adapter
  defdelegate list_conversations(scope, workspace_id), to: @adapter
  defdelegate list_conversations_paginated(scope, workspace_id), to: @adapter
  defdelegate list_conversations_paginated(scope, workspace_id, opts), to: @adapter
  defdelegate get_conversation!(scope, workspace_id, conversation_id), to: @adapter
  defdelegate update_primary_agent(scope, conversation, agent_id), to: @adapter
  defdelegate update_conversation(scope, conversation, attrs), to: @adapter
  defdelegate delete_conversation(scope, conversation), to: @adapter

  # Participants
  defdelegate add_participant(conversation_id, agent_id), to: @adapter
  defdelegate list_participants(conversation_id), to: @adapter

  # Messages
  defdelegate add_message(attrs), to: @adapter
  defdelegate soft_delete_message(message), to: @adapter
  defdelegate restore_message(message), to: @adapter
  defdelegate get_message!(message_id), to: @adapter
  defdelegate update_message_content(message, content), to: @adapter
  defdelegate delete_messages_after(message), to: @adapter
  defdelegate list_messages(conversation_id), to: @adapter
  defdelegate list_messages(conversation_id, opts), to: @adapter
  defdelegate list_messages_paginated(conversation_id, opts \\ []), to: @adapter
  defdelegate latest_summary(conversation_id), to: @adapter
  defdelegate count_messages(conversation_id), to: @adapter
  defdelegate mark_compacted(message_ids), to: @adapter

  # Export
  defdelegate export_as_markdown(conversation_id), to: @adapter
  defdelegate export_as_markdown(conversation_id, opts), to: @adapter
end
