defmodule Summoner.Orchestration.Handoff do
  @moduledoc """
  Transfers control of an invocation from one agent to another.

  Handoff is a one-way transfer — the originating agent stops processing.
  The receiving agent gets a context summary (last N steps + LLM summary
  of earlier steps) injected as its opening message.

  ## Artifacts

  1. A public system message describing the transfer.
  2. An `invocation_events` row with `event_type = handoff_completed`.
  3. `conversations.primary_agent_id` is updated to the receiver.
  """

  require Logger

  alias Summoner.Agents
  alias Summoner.Agents.Server, as: AgentServer
  alias Summoner.Conversations
  alias Summoner.Orchestration

  @default_context_steps 5

  @doc """
  Executes a handoff from the originating agent to a receiving agent.

  `invocation` — the originating invocation (will be marked `handed_off`).
  `receiver_agent_id` — the target agent to hand off to.
  `opts` — optional keyword list:
    - `:context_steps` — number of recent steps to include (default 5)

  Returns `{:ok, child_invocation}` or `{:error, reason}`.
  """
  def execute(invocation, receiver_agent_id, opts \\ []) do
    context_steps = Keyword.get(opts, :context_steps, @default_context_steps)

    with {:ok, receiver} <- load_receiver(receiver_agent_id),
         :ok <- check_capacity(receiver),
         context_summary <- build_context_summary(invocation, context_steps),
         {:ok, child_inv} <- create_child_invocation(invocation, receiver, context_summary),
         {:ok, _inv} <- mark_handed_off(invocation),
         :ok <- write_handoff_artifacts(invocation, receiver, child_inv),
         :ok <- update_conversation_agent(invocation, receiver) do
      # Start the receiver's ReAct loop
      start_receiver(receiver, child_inv, context_summary)
      {:ok, child_inv}
    end
  end

  defp load_receiver(agent_id) do
    case Agents.get_agent_with_provider!(agent_id) do
      nil -> {:error, :receiver_not_found}
      agent -> {:ok, agent}
    end
  rescue
    Ecto.NoResultsError -> {:error, :receiver_not_found}
  end

  defp check_capacity(receiver) do
    case AgentServer.ensure_started(receiver.workspace_id, receiver.id) do
      :ok ->
        # The worker will reject via :at_capacity if full
        :ok

      {:error, reason} ->
        {:error, {:receiver_unavailable, reason}}
    end
  end

  defp build_context_summary(invocation, context_steps) do
    steps = Orchestration.list_steps(invocation.id)
    recent = Enum.take(steps, -context_steps)

    summary_parts =
      Enum.map(recent, fn step ->
        parts = []
        parts = if step.reasoning, do: parts ++ ["Reasoning: #{step.reasoning}"], else: parts
        parts = if step.tool_name, do: parts ++ ["Tool: #{step.tool_name}"], else: parts

        parts =
          if step.tool_output, do: parts ++ ["Output: #{inspect(step.tool_output)}"], else: parts

        Enum.join(parts, "\n")
      end)

    """
    Context from previous agent's work (last #{length(recent)} steps):

    #{Enum.join(summary_parts, "\n---\n")}
    """
  end

  defp create_child_invocation(invocation, receiver, context_summary) do
    Orchestration.create_invocation(%{user: nil}, %{
      workspace_id: invocation.workspace_id,
      agent_id: receiver.id,
      conversation_id: invocation.conversation_id,
      parent_invocation_id: invocation.id,
      depth: (invocation.depth || 0) + 1,
      status: :queued,
      input: %{"context_summary" => context_summary}
    })
  end

  defp mark_handed_off(invocation) do
    Orchestration.update_invocation_status(invocation, :handed_off, %{
      end_reason: :handed_off,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    })
  end

  defp write_handoff_artifacts(invocation, receiver, child_inv) do
    originator_name = get_agent_name(invocation.agent_id)

    # Public system message
    {:ok, _} =
      Conversations.add_message(%{
        conversation_id: invocation.conversation_id,
        invocation_id: invocation.id,
        role: :system,
        content: "#{originator_name} handed off to #{receiver.name}.",
        visibility: :public
      })

    # Invocation event
    {:ok, _} =
      Orchestration.add_event(%{
        invocation_id: child_inv.id,
        agent_id: receiver.id,
        event_type: :handoff_completed,
        visibility: :public,
        summary: "Handoff from #{originator_name} to #{receiver.name}",
        payload: %{
          "originator_agent_id" => invocation.agent_id,
          "receiver_agent_id" => receiver.id,
          "originator_invocation_id" => invocation.id
        }
      })

    :ok
  end

  defp update_conversation_agent(invocation, receiver) do
    if invocation.conversation_id do
      conversation =
        Conversations.get_conversation!(
          %{user: nil},
          invocation.workspace_id,
          invocation.conversation_id
        )

      case Conversations.update_primary_agent(%{user: nil}, conversation, receiver.id) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, {:conversation_update_failed, reason}}
      end
    else
      :ok
    end
  end

  defp get_agent_name(agent_id) do
    case Agents.get_agent_with_provider!(agent_id) do
      %{name: name} -> name
      _ -> "Unknown agent"
    end
  rescue
    _ -> "Unknown agent"
  end

  defp start_receiver(receiver, child_inv, context_summary) do
    AgentServer.invoke_async(receiver.workspace_id, receiver.id, %{
      conversation_id: child_inv.conversation_id,
      message: context_summary,
      scope: %{user: nil}
    })
  end
end
