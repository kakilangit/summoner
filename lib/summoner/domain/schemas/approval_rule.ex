defmodule Summoner.Domain.Schemas.ApprovalRule do
  @moduledoc """
  Schema for workspace-scoped approval rules (Rites).

  Defines when agent actions require human approval before execution.
  Trigger types: tool_call, cost_threshold, output_match.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  @trigger_types ~w(tool_call cost_threshold output_match)
  @timeout_actions ~w(approve reject escalate)

  schema "approval_rules" do
    field :name, :string
    field :trigger_type, :string
    field :trigger_config, :map, default: %{}
    field :approver_roles, {:array, :string}, default: ["admin"]
    field :timeout_s, :integer, default: 3600
    field :timeout_action, :string, default: "reject"
    field :enabled, :boolean, default: true

    belongs_to :workspace, Summoner.Domain.Schemas.Workspace

    timestamps()
  end

  @cast_fields ~w(name trigger_type trigger_config approver_roles timeout_s timeout_action enabled workspace_id)a

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, @cast_fields)
    |> validate_required([:name, :trigger_type, :workspace_id])
    |> validate_inclusion(:trigger_type, @trigger_types)
    |> validate_inclusion(:timeout_action, @timeout_actions)
    |> validate_number(:timeout_s, greater_than: 0, less_than_or_equal_to: 86_400)
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:workspace_id)
  end

  @doc "Returns valid trigger types."
  def trigger_types, do: @trigger_types

  @doc "Returns valid timeout actions."
  def timeout_actions, do: @timeout_actions
end
