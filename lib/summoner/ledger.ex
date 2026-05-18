defmodule Summoner.Ledger do
  @moduledoc """
  The Ledger context — token budget enforcement and usage tracking.

  Handles workspace monthly quotas, per-invocation token caps,
  and persists token usage records for analytics.
  """

  import Ecto.Query, warn: false

  alias Summoner.Conversations.Content
  alias Summoner.Conversations.Message
  alias Summoner.Ledger.{Pricing, TokenUsage}
  alias Summoner.Repo
  alias Summoner.Workspaces.WorkspaceSettings

  @doc """
  Checks whether a workspace has exceeded its monthly token quota.

  Returns `:ok` if under quota or quota is unlimited (null).
  Returns `{:error, :quota_exceeded, %{usage: integer, quota: integer}}`
  if the rolling 30-day token sum exceeds the configured quota.
  """
  def check_workspace_quota(workspace_id) do
    case get_workspace_quota(workspace_id) do
      nil ->
        :ok

      quota ->
        usage = rolling_30_day_usage(workspace_id)

        if usage >= quota do
          {:error, :quota_exceeded, %{usage: usage, quota: quota}}
        else
          :ok
        end
    end
  end

  @doc """
  Checks whether an invocation has exceeded its per-invocation token cap.

  Returns `:ok` if under cap.
  Returns `{:error, :token_limit_reached, %{usage: integer, cap: integer}}`
  if the cumulative token count for the invocation's messages exceeds the cap.
  """
  def check_invocation_cap(invocation_id, max_tokens) do
    usage = invocation_token_usage(invocation_id)

    if usage >= max_tokens do
      {:error, :token_limit_reached, %{usage: usage, cap: max_tokens}}
    else
      :ok
    end
  end

  @doc """
  Checks whether an agent has exceeded its USD budget.

  Returns `:ok` if under budget or budget is unlimited (null).
  Returns `{:error, :budget_exceeded, %{spent: Decimal, budget: Decimal}}`
  if cumulative cost exceeds the configured budget.
  """
  def check_agent_budget(agent_id, budget_usd) do
    case budget_usd do
      nil ->
        :ok

      budget ->
        spent = agent_total_cost(agent_id)

        if Decimal.compare(spent, budget) != :lt do
          {:error, :budget_exceeded, %{spent: spent, budget: budget}}
        else
          :ok
        end
    end
  end

  @doc """
  Checks whether a workspace has exceeded its monthly USD budget.

  Returns `:ok` if under budget or budget is unlimited (null).
  Returns `{:error, :budget_exceeded, %{spent: Decimal, budget: Decimal}}`
  if the rolling 30-day cost exceeds the configured budget.
  """
  def check_workspace_budget(workspace_id) do
    case get_workspace_budget(workspace_id) do
      nil ->
        :ok

      budget ->
        spent = rolling_30_day_cost(workspace_id)

        if Decimal.compare(spent, budget) != :lt do
          {:error, :budget_exceeded, %{spent: spent, budget: budget}}
        else
          :ok
        end
    end
  end

  @doc """
  Estimates USD cost for a model and token counts using the pricing table.
  """
  def estimate_cost(model, prompt_tokens, completion_tokens) do
    Pricing.estimate_cost(model, prompt_tokens, completion_tokens)
  end

  @doc """
  Returns the total USD cost for a specific agent (all time).
  """
  def agent_total_cost(agent_id) do
    TokenUsage
    |> where([t], t.agent_id == ^agent_id)
    |> where([t], not is_nil(t.cost_usd))
    |> select([t], sum(t.cost_usd))
    |> Repo.one()
    |> Kernel.||(Decimal.new(0))
  end

  @doc """
  Returns the rolling 30-day USD cost for a workspace.
  """
  def rolling_30_day_cost(workspace_id) do
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)

    TokenUsage
    |> where([t], t.workspace_id == ^workspace_id)
    |> where([t], t.inserted_at >= ^thirty_days_ago)
    |> where([t], not is_nil(t.cost_usd))
    |> select([t], sum(t.cost_usd))
    |> Repo.one()
    |> Kernel.||(Decimal.new(0))
  end

  @doc """
  Estimates token count from text content.

  Uses the rough heuristic of 1 token ≈ 4 characters.
  Returns 0 for nil or empty content.
  """
  def estimate_tokens(nil), do: 0
  def estimate_tokens(""), do: 0

  def estimate_tokens(blocks) when is_list(blocks) do
    text =
      case blocks do
        [%{type: _} | _] -> Arcanum.Intent.to_text(blocks)
        _ -> Content.text_only(blocks)
      end

    estimate_tokens(text)
  end

  def estimate_tokens(content) when is_binary(content) do
    content
    |> String.length()
    |> div(4)
    |> max(1)
  end

  @doc """
  Estimates token count for a context message map.

  Accounts for role overhead, content, tool call JSON, and tool_call_id.
  Returns an integer token estimate.
  """
  def estimate_message_tokens(%{role: _role, content: content} = msg) do
    base = 4
    content_tokens = estimate_tokens(content)

    tool_calls_tokens =
      case Map.get(msg, :tool_calls) do
        nil -> 0
        [] -> 0
        calls when is_list(calls) -> calls |> Jason.encode!() |> estimate_tokens()
      end

    tool_call_id_tokens =
      case Map.get(msg, :tool_call_id) do
        nil -> 0
        id -> estimate_tokens(id)
      end

    thinking_tokens =
      case Map.get(msg, :thinking) do
        nil -> 0
        t -> estimate_tokens(t)
      end

    base + content_tokens + tool_calls_tokens + tool_call_id_tokens + thinking_tokens
  end

  @doc """
  Estimates total token count for a list of context messages.
  """
  def estimate_context_tokens(messages) when is_list(messages) do
    Enum.reduce(messages, 0, fn msg, acc -> acc + estimate_message_tokens(msg) end)
  end

  @doc """
  Returns the rolling 30-day token usage for a workspace.
  """
  def rolling_30_day_usage(workspace_id) do
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)

    Message
    |> join(:inner, [m], c in assoc(m, :conversation))
    |> where([_m, c], c.workspace_id == ^workspace_id)
    |> where([m, _c], m.inserted_at >= ^thirty_days_ago)
    |> where([m, _c], not is_nil(m.token_count))
    |> select([m, _c], sum(m.token_count))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  Returns the cumulative token usage for an invocation's messages.
  """
  def invocation_token_usage(invocation_id) do
    Message
    |> where([m], m.invocation_id == ^invocation_id)
    |> where([m], not is_nil(m.token_count))
    |> select([m], sum(m.token_count))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  Records token usage for a completed invocation.

  Accepts a map with keys: `workspace_id`, `agent_id`, `provider_id`,
  `invocation_id`, `model`, and token counts from the inference response.
  """
  def record_usage(attrs) do
    %TokenUsage{}
    |> TokenUsage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns token usage aggregated by agent for a workspace.
  """
  def usage_by_agent(workspace_id) do
    TokenUsage
    |> where([t], t.workspace_id == ^workspace_id)
    |> group_by([t], [t.agent_id])
    |> select([t], %{
      agent_id: t.agent_id,
      total_tokens: sum(t.total_tokens),
      prompt_tokens: sum(t.prompt_tokens),
      completion_tokens: sum(t.completion_tokens),
      invocation_count: count(t.id)
    })
    |> Repo.all()
  end

  @doc """
  Returns token usage aggregated by model for a workspace.
  """
  def usage_by_model(workspace_id) do
    TokenUsage
    |> where([t], t.workspace_id == ^workspace_id)
    |> group_by([t], [t.model])
    |> select([t], %{
      model: t.model,
      total_tokens: sum(t.total_tokens),
      prompt_tokens: sum(t.prompt_tokens),
      completion_tokens: sum(t.completion_tokens),
      invocation_count: count(t.id)
    })
    |> Repo.all()
  end

  @doc """
  Returns token usage aggregated by provider for a workspace.
  """
  def usage_by_provider(workspace_id) do
    TokenUsage
    |> where([t], t.workspace_id == ^workspace_id)
    |> group_by([t], [t.provider_id])
    |> select([t], %{
      provider_id: t.provider_id,
      total_tokens: sum(t.total_tokens),
      prompt_tokens: sum(t.prompt_tokens),
      completion_tokens: sum(t.completion_tokens),
      invocation_count: count(t.id)
    })
    |> Repo.all()
  end

  @doc """
  Returns total token usage for a specific agent.
  """
  def usage_for_agent(agent_id) do
    TokenUsage
    |> where([t], t.agent_id == ^agent_id)
    |> select([t], %{
      total_tokens: sum(t.total_tokens),
      prompt_tokens: sum(t.prompt_tokens),
      completion_tokens: sum(t.completion_tokens),
      invocation_count: count(t.id)
    })
    |> Repo.one()
  end

  @doc """
  Returns total token usage for a specific provider.
  """
  def usage_for_provider(provider_id) do
    TokenUsage
    |> where([t], t.provider_id == ^provider_id)
    |> select([t], %{
      total_tokens: sum(t.total_tokens),
      prompt_tokens: sum(t.prompt_tokens),
      completion_tokens: sum(t.completion_tokens),
      invocation_count: count(t.id)
    })
    |> Repo.one()
  end

  @doc """
  Returns token usage by model for a specific provider.
  """
  def usage_by_model_for_provider(provider_id) do
    TokenUsage
    |> where([t], t.provider_id == ^provider_id)
    |> group_by([t], [t.model])
    |> select([t], %{
      model: t.model,
      total_tokens: sum(t.total_tokens),
      prompt_tokens: sum(t.prompt_tokens),
      completion_tokens: sum(t.completion_tokens),
      invocation_count: count(t.id)
    })
    |> order_by([t], desc: sum(t.total_tokens))
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Internal
  # -------------------------------------------------------------------

  defp get_workspace_quota(workspace_id) do
    WorkspaceSettings
    |> where([s], s.workspace_id == ^workspace_id)
    |> select([s], s.token_quota_monthly)
    |> Repo.one()
  end

  defp get_workspace_budget(workspace_id) do
    WorkspaceSettings
    |> where([s], s.workspace_id == ^workspace_id)
    |> select([s], s.budget_usd_monthly)
    |> Repo.one()
  end
end
