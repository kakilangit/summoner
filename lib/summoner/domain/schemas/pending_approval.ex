defmodule Summoner.Domain.Schemas.PendingApproval do
  @moduledoc """
  Schema for pending approval requests.

  Created when an agent action triggers an approval rule.
  Tracks the approval lifecycle: pending → approved/rejected/expired.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  @statuses ~w(pending approved rejected expired)

  schema "pending_approvals" do
    field :status, :string, default: "pending"
    field :action_summary, :string
    field :action_details, :map, default: %{}
    field :decided_at, :utc_datetime_usec
    field :decision_note, :string

    belongs_to :rule, Summoner.Domain.Schemas.ApprovalRule
    belongs_to :invocation, Summoner.Domain.Schemas.Invocation
    belongs_to :agent, Summoner.Domain.Schemas.Agent
    belongs_to :decided_by_user, Summoner.Domain.Schemas.User, foreign_key: :decided_by
    belongs_to :workspace, Summoner.Domain.Schemas.Workspace

    timestamps()
  end

  @cast_fields ~w(status action_summary action_details rule_id invocation_id agent_id decided_by decided_at decision_note workspace_id)a

  def changeset(approval, attrs) do
    approval
    |> cast(attrs, @cast_fields)
    |> validate_required([:action_summary, :rule_id, :invocation_id, :agent_id, :workspace_id])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:rule_id)
    |> foreign_key_constraint(:invocation_id)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:workspace_id)
  end

  @doc "Returns valid statuses."
  def statuses, do: @statuses
end
