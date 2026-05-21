defmodule Summoner.Domain.Schemas.Agent do
  @moduledoc """
  Schema for Agents — the universal identity for anything that can act
  in an orchestration context (local inference agent, remote A2A agent).

  The `agents` table is thin: identity (name, callname), type, role,
  workspace, and soft-delete. Type-specific configuration lives in
  detail tables: `local_agents` for inference/ReAct config, and
  `remote_agents` for A2A client config.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.AgentFailoverEntry
  alias Summoner.Domain.Schemas.LocalAgent
  alias Summoner.Domain.Schemas.RemoteAgent
  alias Summoner.Domain.Schemas.Workspace

  @types ~w(local remote)a
  @roles ~w(autonomous worker)a
  @failover_strategies ~w(auto manual notify_then_auto)a

  schema "agents" do
    field :name, :string
    field :callname, :string
    field :type, Ecto.Enum, values: @types, default: :local
    field :role, Ecto.Enum, values: @roles, default: :autonomous
    field :failover_strategy, Ecto.Enum, values: @failover_strategies, default: :auto
    field :failover_delay_ms, :integer, default: 0
    field :max_failover_depth, :integer, default: 3
    field :deleted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace

    has_one :local_agent, LocalAgent
    has_one :remote_agent, RemoteAgent
    has_many :failover_chain, AgentFailoverEntry, preload_order: [asc: :position]

    timestamps()
  end

  @doc "All supported types."
  def types, do: @types

  @doc "All supported failover strategies."
  def failover_strategies, do: @failover_strategies

  @doc "Failover strategy options with descriptive labels for form selects."
  def failover_strategy_options do
    [
      {"Auto — failover immediately when primary fails", :auto},
      {"Manual — wait for user approval before failover", :manual},
      {"Notify then Auto — notify, then failover after delay", :notify_then_auto}
    ]
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
    :type,
    :role,
    :workspace_id,
    :failover_strategy,
    :failover_delay_ms,
    :max_failover_depth
  ]
  @required_fields [:name, :role, :workspace_id]

  @doc """
  Changeset for creating or updating an agent.
  """
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_callname_if_present()
    |> validate_number(:failover_delay_ms, greater_than_or_equal_to: 0)
    |> validate_number(:max_failover_depth,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 10
    )
    |> unique_constraint([:workspace_id, :callname],
      name: :agents_workspace_id_callname_active_index,
      message: "already taken by another summon or envoy in this realm"
    )
    |> foreign_key_constraint(:workspace_id)
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
  Returns a short human-readable description of the agent.

  For local agents this is the personality. For remote agents it is the
  description from the cached A2A agent card. Returns `nil` when neither
  is available.
  """
  def description(%__MODULE__{local_agent: %LocalAgent{personality: p}})
      when is_binary(p) and p != "", do: p

  def description(%__MODULE__{
        remote_agent: %RemoteAgent{cached_agent_card: %{"description" => d}}
      })
      when is_binary(d) and d != "", do: d

  def description(%__MODULE__{}), do: nil

  @doc """
  Extracts an inference snapshot map from a local agent with its provider preloaded.

  Returns `%{provider_name: ..., model_name: ...}` for embedding in
  conversations, invocations, messages, and pipeline run stages.

  Only meaningful for local agents. Returns nil provider/model for remote agents.
  """
  def inference_snapshot(%__MODULE__{local_agent: %LocalAgent{} = local}) do
    provider_name =
      case local.provider do
        %Summoner.Domain.Schemas.Provider{name: name} -> name
        _ -> nil
      end

    %{provider_name: provider_name, model_name: local.model}
  end

  def inference_snapshot(%__MODULE__{}) do
    %{provider_name: nil, model_name: nil}
  end
end
