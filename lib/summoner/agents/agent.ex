defmodule Summoner.Agents.Agent do
  @moduledoc """
  Schema for Agents — the universal identity for anything that can act
  in an orchestration context (local inference agent, remote A2A agent).

  The `agents` table is thin: identity (name, callname), type, role,
  workspace, and soft-delete. Type-specific configuration lives in
  detail tables: `local_agents` for inference/ReAct config, and
  `remote_agents` for A2A client config.
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Agents.LocalAgent
  alias Summoner.Agents.RemoteAgent
  alias Summoner.Workspaces.Workspace

  @types ~w(local remote)a
  @roles ~w(autonomous worker)a

  schema "agents" do
    field :name, :string
    field :callname, :string
    field :type, Ecto.Enum, values: @types, default: :local
    field :role, Ecto.Enum, values: @roles, default: :autonomous
    field :deleted_at, :utc_datetime_usec

    belongs_to :workspace, Workspace

    has_one :local_agent, LocalAgent
    has_one :remote_agent, RemoteAgent

    timestamps()
  end

  @doc "All supported types."
  def types, do: @types

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

  @cast_fields [:name, :callname, :type, :role, :workspace_id]
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
    |> unique_constraint([:workspace_id, :callname],
      name: :agents_workspace_id_callname_active_index
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
  Extracts an inference snapshot map from a local agent with its provider preloaded.

  Returns `%{provider_name: ..., model_name: ...}` for embedding in
  conversations, invocations, messages, and pipeline run stages.

  Only meaningful for local agents. Returns nil provider/model for remote agents.
  """
  def inference_snapshot(%__MODULE__{local_agent: %LocalAgent{} = local}) do
    provider_name =
      case local.provider do
        %Summoner.Providers.Provider{name: name} -> name
        _ -> nil
      end

    %{provider_name: provider_name, model_name: local.model}
  end

  def inference_snapshot(%__MODULE__{}) do
    %{provider_name: nil, model_name: nil}
  end
end
