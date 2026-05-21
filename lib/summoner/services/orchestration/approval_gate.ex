defmodule Summoner.Services.Orchestration.ApprovalGate do
  @moduledoc """
  Service that checks tool calls against approval rules before execution.

  Called from ReactLoop to pause invocations when human approval is needed.
  """

  alias Summoner.Domain.Policies.Orchestration.ApprovalCheck
  alias Summoner.Ports.Persistence.Approvals
  alias Summoner.Ports.Persistence.Orchestration

  @doc """
  Checks a batch of tool calls against approval rules for the workspace.

  Returns `:proceed` if no approval is needed, or `{:paused, approval}`
  if the invocation should be paused.
  """
  @spec check_calls(map(), [map()]) :: :proceed | {:paused, struct()}
  def check_calls(state, tool_calls) do
    rules = Approvals.list_enabled_rules(state.invocation.workspace_id)

    if rules == [] do
      :proceed
    else
      check_calls_against_rules(state, tool_calls, rules)
    end
  end

  defp check_calls_against_rules(state, tool_calls, rules) do
    Enum.find_value(tool_calls, :proceed, fn tool_call ->
      tool_name = tool_call.function.name
      tool_args = parse_args(tool_call.function.arguments)

      case ApprovalCheck.check(rules, tool_name, tool_args) do
        :proceed ->
          nil

        {:requires_approval, rule} ->
          pause_for_approval(state, tool_call, rule, tool_name, tool_args)
      end
    end)
  end

  defp pause_for_approval(state, tool_call, rule, tool_name, tool_args) do
    summary = ApprovalCheck.action_summary(tool_name, tool_args)
    scope = %{user: nil}

    # Update invocation to awaiting_approval
    Orchestration.update_invocation_status(state.invocation, :awaiting_approval, %{
      paused_at: DateTime.utc_now(),
      paused_tool_call: %{
        "id" => tool_call.id,
        "name" => tool_name,
        "arguments" => tool_call.function.arguments
      }
    })

    case Approvals.create_pending(scope, %{
           rule_id: rule.id,
           invocation_id: state.invocation.id,
           agent_id: state.agent.id,
           workspace_id: state.invocation.workspace_id,
           action_summary: summary,
           action_details: %{
             "tool_name" => tool_name,
             "tool_args" => tool_args,
             "tool_call_id" => tool_call.id
           }
         }) do
      {:ok, approval} ->
        {:paused, approval}

      {:error, _changeset} ->
        # If we can't create the approval record, proceed anyway
        :proceed
    end
  end

  defp parse_args(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{}
    end
  end

  defp parse_args(args) when is_map(args), do: args
  defp parse_args(_), do: %{}
end
