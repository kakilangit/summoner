defmodule Summoner.Domain.Schemas.WorkspaceSettings do
  @moduledoc """
  Schema for workspace-level settings.

  Controls context window size, tool output limits, quotas/budgets,
  operational harness, and default timeout values for summons.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Workspace

  @default_context_window_messages 20
  @default_max_tool_output_chars 32_000
  @default_step_timeout_s 60
  @default_total_timeout_s 300
  @default_max_tool_concurrency 5

  schema "workspace_settings" do
    field :context_window_messages, :integer, default: @default_context_window_messages
    field :max_tool_output_chars, :integer, default: @default_max_tool_output_chars
    field :token_quota_monthly, :integer
    field :budget_usd_monthly, :decimal
    field :harness, :string
    field :default_step_timeout_s, :integer, default: @default_step_timeout_s
    field :default_total_timeout_s, :integer, default: @default_total_timeout_s
    field :default_max_tool_concurrency, :integer, default: @default_max_tool_concurrency

    belongs_to :workspace, Workspace

    timestamps()
  end

  @doc """
  Returns the default number of context window messages.
  """
  def default_context_window_messages, do: @default_context_window_messages

  @doc """
  Returns the default maximum tool output characters.
  """
  def default_max_tool_output_chars, do: @default_max_tool_output_chars

  @doc """
  Returns the default step timeout in seconds.
  """
  def default_step_timeout_s, do: @default_step_timeout_s

  @doc """
  Returns the default total timeout in seconds.
  """
  def default_total_timeout_s, do: @default_total_timeout_s

  @doc """
  Returns the default max tool concurrency.
  """
  def default_max_tool_concurrency, do: @default_max_tool_concurrency

  @doc """
  Changeset for creating or updating workspace settings.
  """
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :context_window_messages,
      :max_tool_output_chars,
      :token_quota_monthly,
      :budget_usd_monthly,
      :harness,
      :default_step_timeout_s,
      :default_total_timeout_s,
      :default_max_tool_concurrency,
      :workspace_id
    ])
    |> validate_required([:context_window_messages, :workspace_id])
    |> validate_number(:context_window_messages, greater_than: 0)
    |> validate_number(:max_tool_output_chars, greater_than: 0)
    |> validate_number(:token_quota_monthly, greater_than: 0)
    |> validate_number(:budget_usd_monthly, greater_than: 0)
    |> validate_number(:default_step_timeout_s, greater_than: 0, less_than_or_equal_to: 600)
    |> validate_number(:default_total_timeout_s, greater_than: 0, less_than_or_equal_to: 3_600)
    |> validate_number(:default_max_tool_concurrency, greater_than: 0)
    |> unique_constraint(:workspace_id)
    |> foreign_key_constraint(:workspace_id)
  end
end
