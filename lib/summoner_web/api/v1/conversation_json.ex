defmodule SummonerWeb.API.V1.ConversationJSON do
  @moduledoc "JSON rendering for conversations and messages."

  import SummonerWeb.API.PaginationJSON

  def index(%{page: page}) do
    %{items: Enum.map(page.entries, &conversation_data/1), meta: page_meta(page)}
  end

  def show(%{conversation: conversation}) do
    conversation_data(conversation)
  end

  def messages(%{page: page}) do
    %{items: Enum.map(page.entries, &message_data/1), meta: page_meta(page)}
  end

  defp conversation_data(c) do
    %{
      id: c.id,
      title: c.title,
      kind: c.kind,
      provider_name: c.provider_name,
      model_name: c.model_name,
      workspace_id: c.workspace_id,
      primary_agent_id: c.primary_agent_id,
      user_id: c.user_id,
      swarm_id: c.swarm_id,
      inserted_at: c.inserted_at,
      updated_at: c.updated_at
    }
  end

  defp message_data(m) do
    %{
      id: m.id,
      role: m.role,
      visibility: m.visibility,
      kind: m.kind,
      content: m.content,
      tool_call_id: m.tool_call_id,
      tool_calls: m.tool_calls,
      token_count: m.token_count,
      thinking: m.thinking,
      provider_name: m.provider_name,
      model_name: m.model_name,
      agent_id: m.agent_id,
      conversation_id: m.conversation_id,
      invocation_id: m.invocation_id,
      inserted_at: m.inserted_at
    }
  end
end
