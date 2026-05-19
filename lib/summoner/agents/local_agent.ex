defmodule Summoner.Agents.LocalAgent do
  @moduledoc """
  Schema for local agent configuration — inference, ReAct loop, and provider settings.

  Each local agent is bound to a provider and model, and carries configuration
  for the ReAct loop (steps, timeouts, token limits). This is the detail table
  for agents with `type: :local`.

  Uses the parent `agents.id` as its primary key (`agent_id`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Summoner.Agents.Agent
  alias Summoner.MediaProviders.MediaProvider
  alias Summoner.Providers.Provider

  @primary_key {:agent_id, Nulid.Ecto, autogenerate: false}
  @foreign_key_type Nulid.Ecto
  @timestamps_opts [type: :utc_datetime_usec]

  schema "local_agents" do
    field :model, :string
    field :system_prompt, :string
    field :personality, :string
    field :max_steps, :integer, default: 10
    field :max_concurrent_invocations, :integer, default: 1
    field :max_delegation_concurrency, :integer, default: 3
    field :max_tokens_per_invocation, :integer, default: 50_000
    field :context_length, :integer
    field :step_timeout_s, :integer, default: 60
    field :total_timeout_s, :integer, default: 300
    field :stream_tokens_to_observability, :boolean, default: false
    field :budget_usd, :decimal

    belongs_to :agent, Agent, references: :id, define_field: false
    belongs_to :provider, Provider
    belongs_to :media_provider, MediaProvider
  end

  @cast_fields [
    :model,
    :system_prompt,
    :personality,
    :max_steps,
    :max_concurrent_invocations,
    :max_delegation_concurrency,
    :max_tokens_per_invocation,
    :context_length,
    :step_timeout_s,
    :total_timeout_s,
    :stream_tokens_to_observability,
    :budget_usd,
    :provider_id,
    :media_provider_id
  ]

  @required_fields [:model, :provider_id]

  @doc """
  Changeset for creating or updating a local agent's configuration.
  """
  def changeset(local_agent, attrs) do
    local_agent
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_number(:max_steps, greater_than: 0)
    |> validate_number(:max_concurrent_invocations, greater_than: 0)
    |> validate_number(:max_delegation_concurrency, greater_than: 0)
    |> validate_number(:max_tokens_per_invocation, greater_than: 0)
    |> validate_number(:context_length, greater_than: 0)
    |> validate_number(:step_timeout_s, greater_than: 0, less_than_or_equal_to: 600)
    |> validate_number(:total_timeout_s, greater_than: 0, less_than_or_equal_to: 3_600)
    |> validate_number(:budget_usd, greater_than: 0)
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:media_provider_id)
  end
end
