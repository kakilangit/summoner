defmodule SummonerWeb.API.V1.InvocationJSON do
  @moduledoc "JSON rendering for invocations, steps, and events."

  def invocation(%{invocation: inv, messages: messages}) do
    %{
      data: %{
        invocation_id: inv.id,
        status: inv.status,
        end_reason: inv.end_reason,
        output: inv.output,
        agent_id: inv.agent_id,
        conversation_id: inv.conversation_id,
        started_at: inv.started_at,
        completed_at: inv.completed_at,
        provider_name: inv.provider_name,
        model_name: inv.model_name,
        messages: Enum.map(messages, &message_data/1)
      }
    }
  end

  def show(%{invocation: inv}) do
    %{data: invocation_data(inv)}
  end

  def steps(%{steps: steps}) do
    %{data: Enum.map(steps, &step_data/1)}
  end

  def events(%{events: events}) do
    %{data: Enum.map(events, &event_data/1)}
  end

  defp invocation_data(inv) do
    %{
      id: inv.id,
      status: inv.status,
      end_reason: inv.end_reason,
      input: inv.input,
      output: inv.output,
      depth: inv.depth,
      agent_id: inv.agent_id,
      conversation_id: inv.conversation_id,
      workspace_id: inv.workspace_id,
      parent_invocation_id: inv.parent_invocation_id,
      started_at: inv.started_at,
      completed_at: inv.completed_at,
      provider_name: inv.provider_name,
      model_name: inv.model_name,
      inserted_at: inv.inserted_at
    }
  end

  defp step_data(s) do
    %{
      id: s.id,
      step_number: s.step_number,
      reasoning: s.reasoning,
      tool_name: s.tool_name,
      tool_input: s.tool_input,
      tool_output: s.tool_output,
      status: s.status,
      inserted_at: s.inserted_at
    }
  end

  defp event_data(e) do
    %{
      id: e.id,
      event_type: e.event_type,
      visibility: e.visibility,
      summary: e.summary,
      payload: e.payload,
      agent_id: e.agent_id,
      inserted_at: e.inserted_at
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
      agent_id: m.agent_id,
      inserted_at: m.inserted_at
    }
  end
end
