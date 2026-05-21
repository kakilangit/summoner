defmodule Summoner.Adapters.Persistence.Approvals do
  @moduledoc """
  Persistence adapter for approval rules and pending approvals (Rites).
  """

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Pagination
  alias Summoner.Domain.Schemas.ApprovalRule
  alias Summoner.Domain.Schemas.PendingApproval
  alias Summoner.Repo

  @behaviour Summoner.Ports.Persistence.Approvals.Adapter

  # -- Approval Rules --------------------------------------------------------

  def create_rule(%{user: _user}, attrs) do
    %ApprovalRule{}
    |> ApprovalRule.changeset(attrs)
    |> Repo.insert()
  end

  def list_rules(%{user: _user}, workspace_id) do
    ApprovalRule
    |> where([r], r.workspace_id == ^workspace_id)
    |> order_by([r], asc: r.name)
    |> Repo.all()
  end

  def list_rules_paginated(%{user: _user}, workspace_id, opts \\ []) do
    ApprovalRule
    |> where([r], r.workspace_id == ^workspace_id)
    |> Pagination.paginate(opts)
  end

  def get_rule!(%{user: _user}, workspace_id, rule_id) do
    ApprovalRule
    |> where([r], r.workspace_id == ^workspace_id)
    |> Repo.get!(rule_id)
  end

  def update_rule(%{user: _user}, %ApprovalRule{} = rule, attrs) do
    rule
    |> ApprovalRule.changeset(attrs)
    |> Repo.update()
  end

  def delete_rule(%{user: _user}, %ApprovalRule{} = rule) do
    Repo.delete(rule)
  end

  def change_rule(%ApprovalRule{} = rule, attrs \\ %{}) do
    ApprovalRule.changeset(rule, attrs)
  end

  def list_enabled_rules(workspace_id) do
    ApprovalRule
    |> where([r], r.workspace_id == ^workspace_id and r.enabled == true)
    |> order_by([r], asc: r.name)
    |> Repo.all()
  end

  # -- Pending Approvals -----------------------------------------------------

  def create_pending(%{user: _user}, attrs) do
    %PendingApproval{}
    |> PendingApproval.changeset(attrs)
    |> Repo.insert()
  end

  def list_pending(%{user: _user}, workspace_id) do
    PendingApproval
    |> where([p], p.workspace_id == ^workspace_id and p.status == "pending")
    |> order_by([p], asc: p.inserted_at)
    |> preload([:rule, :agent])
    |> Repo.all()
  end

  def list_pending_paginated(%{user: _user}, workspace_id, opts \\ []) do
    PendingApproval
    |> where([p], p.workspace_id == ^workspace_id)
    |> preload([:rule, :agent])
    |> Pagination.paginate(opts)
  end

  def get_pending!(%{user: _user}, workspace_id, approval_id) do
    PendingApproval
    |> where([p], p.workspace_id == ^workspace_id)
    |> preload([:rule, :agent, :invocation])
    |> Repo.get!(approval_id)
  end

  def decide(%PendingApproval{} = approval, decision, user_id, note \\ nil) do
    approval
    |> Ecto.Changeset.change(%{
      status: decision,
      decided_by: user_id,
      decided_at: DateTime.utc_now(),
      decision_note: note
    })
    |> Repo.update()
  end

  def count_pending(workspace_id) do
    PendingApproval
    |> where([p], p.workspace_id == ^workspace_id and p.status == "pending")
    |> Repo.aggregate(:count, :id)
  end

  def list_expired(cutoff) do
    PendingApproval
    |> where([p], p.status == "pending" and p.inserted_at < ^cutoff)
    |> preload(:rule)
    |> Repo.all()
  end
end
