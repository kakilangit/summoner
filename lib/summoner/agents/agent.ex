defmodule Summoner.Agents.Agent do
  @moduledoc """
  Schema for Agents — the AI agents within a workspace.

  Each Agent is bound to a provider and model, has a role
  (manager, worker, or autonomous), and carries configuration
  for the ReAct loop (steps, timeouts, token limits).
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.MediaProviders.MediaProvider
  alias Summoner.Providers.Provider
  alias Summoner.Workspaces.Workspace

  @roles ~w(autonomous worker)a

  schema "agents" do
    field :name, :string
    field :callname, :string
    field :system_prompt, :string
    field :personality, :string
    field :model, :string
    field :role, Ecto.Enum, values: @roles, default: :autonomous
    field :max_steps, :integer, default: 10
    field :max_concurrent_invocations, :integer, default: 1
    field :max_delegation_concurrency, :integer, default: 3
    field :max_tokens_per_invocation, :integer, default: 50_000
    field :context_length, :integer
    field :step_timeout_s, :integer, default: 60
    field :total_timeout_s, :integer, default: 300
    field :stream_tokens_to_observability, :boolean, default: false
    field :budget_usd, :decimal

    belongs_to :workspace, Workspace
    belongs_to :provider, Provider
    belongs_to :media_provider, MediaProvider

    timestamps()
  end

  @doc "All supported roles."
  def roles, do: @roles

  @doc "Role options with descriptive labels for form selects."
  def role_options do
    [
      {"Autonomous — independent agent, speaks publicly", :autonomous},
      {"Worker — receives delegated tasks, internal messages", :worker}
    ]
  end

  @doc "Human-readable description of a role."
  def role_description(:autonomous) do
    "Runs independently. Can delegate subtasks to linked workers. " <>
      "Speaks publicly in conversations. Used for direct chat and as pipeline orchestrators."
  end

  def role_description(:worker) do
    "Receives delegated tasks from other summons. Works in isolation " <>
      "with only the task description (no parent conversation). " <>
      "Writes internal messages only."
  end

  def role_description(_), do: ""

  @cast_fields [
    :name,
    :callname,
    :system_prompt,
    :personality,
    :model,
    :role,
    :max_steps,
    :max_concurrent_invocations,
    :max_delegation_concurrency,
    :max_tokens_per_invocation,
    :context_length,
    :step_timeout_s,
    :total_timeout_s,
    :stream_tokens_to_observability,
    :budget_usd,
    :workspace_id,
    :provider_id,
    :media_provider_id
  ]

  @required_fields [:name, :model, :role, :workspace_id, :provider_id]

  @doc """
  Changeset for creating or updating an agent.
  """
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_callname_if_present()
    |> validate_number(:max_steps, greater_than: 0)
    |> validate_number(:max_concurrent_invocations, greater_than: 0)
    |> validate_number(:max_delegation_concurrency, greater_than: 0)
    |> validate_number(:max_tokens_per_invocation, greater_than: 0)
    |> validate_number(:context_length, greater_than: 0)
    |> validate_number(:step_timeout_s, greater_than: 0, less_than_or_equal_to: 600)
    |> validate_number(:total_timeout_s, greater_than: 0, less_than_or_equal_to: 3_600)
    |> validate_number(:budget_usd, greater_than: 0)
    |> unique_constraint([:workspace_id, :callname])
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:media_provider_id)
  end

  # Only validate callname format when it has a value.
  # On new records during live validation, callname may be blank
  # (it gets auto-generated at insert time).
  defp validate_callname_if_present(changeset) do
    callname = get_field(changeset, :callname)

    if blank?(callname) && is_nil(changeset.data.id) do
      # New record, callname not yet set — skip validation during phx-change
      changeset
    else
      changeset
      |> validate_required([:callname])
      |> validate_length(:callname, min: 1, max: 100)
      |> validate_format(:callname, ~r/\A[a-z][a-z0-9_]*\z/,
        message: "must be lowercase letters, digits, and underscores, starting with a letter"
      )
    end
  end

  @doc "Converts a display name to a snake_case callname."
  def to_callname(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.replace(~r/^_|_$/, "")
  end

  defp blank?(nil), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false

  @doc """
  Extracts an inference snapshot map from an agent with its provider preloaded.

  Returns `%{provider_name: ..., model_name: ...}` for embedding in
  conversations, invocations, messages, and pipeline run stages.
  """
  def inference_snapshot(%__MODULE__{} = agent) do
    provider_name =
      case agent.provider do
        %Provider{name: name} -> name
        _ -> nil
      end

    %{provider_name: provider_name, model_name: agent.model}
  end
end
