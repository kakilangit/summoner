defmodule Summoner.Domain.Schemas.TokenUsage do
  @moduledoc """
  Schema for token usage records.

  Each record captures the token consumption of a single invocation,
  denormalized with agent, provider, and model for efficient analytics.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.Invocation
  alias Summoner.Domain.Schemas.Provider
  alias Summoner.Domain.Schemas.Workspace

  schema "token_usages" do
    field :prompt_tokens, :integer, default: 0
    field :completion_tokens, :integer, default: 0
    field :total_tokens, :integer, default: 0
    field :cost_usd, :decimal
    field :model, :string
    field :estimated, :boolean, default: false

    belongs_to :workspace, Workspace
    belongs_to :agent, Agent
    belongs_to :provider, Provider
    belongs_to :invocation, Invocation

    timestamps(updated_at: false)
  end

  @required_fields ~w(
    workspace_id agent_id provider_id invocation_id
    model total_tokens
  )a

  @optional_fields ~w(prompt_tokens completion_tokens estimated cost_usd)a

  def changeset(token_usage, attrs) do
    token_usage
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:total_tokens, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:invocation_id)
  end
end
