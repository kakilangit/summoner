defmodule Summoner.Domain.Policies.Orchestration.ApprovalCheck do
  @moduledoc """
  Pure policy for checking whether an agent action requires approval.

  Receives rules as input (no port calls). Returns `:proceed` or
  `{:requires_approval, rule}`.
  """

  @doc """
  Checks tool call against approval rules.

  Returns `:proceed` if no rule matches, or `{:requires_approval, rule}`
  with the first matching rule.
  """
  @spec check([struct()], String.t(), map()) :: :proceed | {:requires_approval, struct()}
  def check(rules, tool_name, tool_args) do
    rules
    |> Enum.filter(& &1.enabled)
    |> Enum.find_value(:proceed, fn rule ->
      if matches?(rule, tool_name, tool_args) do
        {:requires_approval, rule}
      end
    end)
  end

  @doc "Checks if a rule matches the given tool call."
  @spec matches?(struct(), String.t(), map()) :: boolean()
  def matches?(%{trigger_type: "tool_call"} = rule, tool_name, _tool_args) do
    tool_names = get_in(rule.trigger_config, ["tool_names"]) || []
    tool_name in tool_names
  end

  def matches?(%{trigger_type: "output_match"} = rule, _tool_name, tool_args) do
    patterns = get_in(rule.trigger_config, ["patterns"]) || []
    args_string = inspect(tool_args)

    Enum.any?(patterns, fn pattern ->
      case Regex.compile(pattern) do
        {:ok, regex} -> Regex.match?(regex, args_string)
        {:error, _} -> false
      end
    end)
  end

  def matches?(%{trigger_type: "cost_threshold"}, _tool_name, _tool_args) do
    # Cost threshold is checked at invocation level, not per-tool
    false
  end

  def matches?(_rule, _tool_name, _tool_args), do: false

  @doc """
  Checks if invocation cost exceeds any cost_threshold rules.

  Returns `:proceed` or `{:requires_approval, rule}`.
  """
  @spec check_cost([struct()], number()) :: :proceed | {:requires_approval, struct()}
  def check_cost(rules, current_cost_usd) do
    rules
    |> Enum.filter(&(&1.enabled and &1.trigger_type == "cost_threshold"))
    |> Enum.find_value(:proceed, fn rule ->
      threshold = get_in(rule.trigger_config, ["threshold_usd"]) || 0

      if current_cost_usd >= threshold do
        {:requires_approval, rule}
      end
    end)
  end

  @doc "Generates a human-readable summary for a tool call."
  @spec action_summary(String.t(), map()) :: String.t()
  def action_summary(tool_name, tool_args) do
    args_preview =
      tool_args
      |> inspect(limit: 200, pretty: false)
      |> String.slice(0, 200)

    "Tool call: #{tool_name}(#{args_preview})"
  end
end
