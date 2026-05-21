defmodule Summoner.Adapters.Persistence.EventRules do
  @moduledoc "Ecto persistence adapter for event rules (Omens)."

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Pagination
  alias Summoner.Domain.Schemas.EventRule
  alias Summoner.Domain.Schemas.EventRuleExecution
  alias Summoner.Repo

  @behaviour Summoner.Ports.Persistence.EventRules.Adapter

  @impl true
  def create_event_rule(%{user: _user}, attrs) do
    %EventRule{}
    |> EventRule.changeset(attrs)
    |> Repo.insert()
  end

  @impl true
  def update_event_rule(%{user: _user}, %EventRule{} = event_rule, attrs) do
    event_rule
    |> EventRule.changeset(attrs)
    |> Repo.update()
  end

  @impl true
  def delete_event_rule(%{user: _user}, %EventRule{} = event_rule) do
    Repo.delete(event_rule)
  end

  @impl true
  def get_event_rule!(%{user: _user}, workspace_id, id) do
    EventRule
    |> where([r], r.workspace_id == ^workspace_id)
    |> Repo.get!(id)
  end

  @impl true
  def list_event_rules(%{user: _user}, workspace_id, opts) do
    EventRule
    |> where([r], r.workspace_id == ^workspace_id)
    |> order_by([r], [asc: r.priority, desc: r.inserted_at])
    |> maybe_filter(opts)
    |> Repo.all()
  end

  @impl true
  def list_event_rules_paginated(%{user: _user}, workspace_id, opts) do
    EventRule
    |> where([r], r.workspace_id == ^workspace_id)
    |> maybe_filter(opts)
    |> Pagination.paginate(opts)
  end

  @impl true
  def list_enabled_rules_for_event(workspace_id, event_type) do
    EventRule
    |> where([r], r.workspace_id == ^workspace_id)
    |> where([r], r.enabled == true)
    |> where([r], r.event_type == ^event_type)
    |> order_by([r], asc: r.priority)
    |> Repo.all()
  end

  @impl true
  def record_fire(id) do
    now = DateTime.utc_now()

    EventRule
    |> where([r], r.id == ^id)
    |> Repo.update_all(inc: [fire_count: 1], set: [last_fired_at: now])

    :ok
  end

  @impl true
  def create_execution(attrs) do
    %EventRuleExecution{}
    |> EventRuleExecution.changeset(attrs)
    |> Repo.insert()
  end

  @impl true
  def update_execution(%EventRuleExecution{} = execution, attrs) do
    execution
    |> EventRuleExecution.changeset(attrs)
    |> Repo.update()
  end

  @impl true
  def list_executions(event_rule_id, opts) do
    EventRuleExecution
    |> where([e], e.event_rule_id == ^event_rule_id)
    |> order_by([e], desc: e.inserted_at)
    |> maybe_filter_executions(opts)
    |> Repo.all()
  end

  @impl true
  def list_executions_paginated(event_rule_id, opts) do
    EventRuleExecution
    |> where([e], e.event_rule_id == ^event_rule_id)
    |> maybe_filter_executions(opts)
    |> Pagination.paginate(opts)
  end

  @impl true
  def change_event_rule(%EventRule{} = event_rule, attrs \\ %{}) do
    EventRule.changeset(event_rule, attrs)
  end

  defp maybe_filter(query, opts) do
    Enum.reduce(opts, query, fn
      {:event_type, type}, q when not is_nil(type) ->
        where(q, [r], r.event_type == ^type)

      {:enabled, enabled}, q when is_boolean(enabled) ->
        where(q, [r], r.enabled == ^enabled)

      {:action_type, type}, q when not is_nil(type) ->
        where(q, [r], r.action_type == ^type)

      _, q ->
        q
    end)
  end

  defp maybe_filter_executions(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, q when not is_nil(status) ->
        where(q, [e], e.status == ^status)

      _, q ->
        q
    end)
  end
end
