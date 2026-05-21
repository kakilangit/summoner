defmodule Summoner.Adapters.Persistence.Webhooks do
  @moduledoc "Ecto persistence adapter for webhooks (Beacons)."

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Pagination
  alias Summoner.Domain.Schemas.Webhook
  alias Summoner.Repo

  @behaviour Summoner.Ports.Persistence.Webhooks.Adapter

  @impl true
  def create_webhook(%{user: _user}, attrs) do
    %Webhook{}
    |> Webhook.changeset(attrs)
    |> Repo.insert()
  end

  @impl true
  def update_webhook(%{user: _user}, %Webhook{} = webhook, attrs) do
    webhook
    |> Webhook.changeset(attrs)
    |> Repo.update()
  end

  @impl true
  def delete_webhook(%{user: _user}, %Webhook{} = webhook) do
    Repo.delete(webhook)
  end

  @impl true
  def get_webhook!(%{user: _user}, workspace_id, id) do
    Webhook
    |> where([w], w.workspace_id == ^workspace_id)
    |> Repo.get!(id)
  end

  @impl true
  def get_webhook(id) do
    Repo.get(Webhook, id)
  end

  @impl true
  def list_webhooks(%{user: _user}, workspace_id, opts) do
    Webhook
    |> where([w], w.workspace_id == ^workspace_id)
    |> order_by([w], desc: w.inserted_at)
    |> maybe_filter(opts)
    |> Repo.all()
  end

  @impl true
  def list_webhooks_paginated(%{user: _user}, workspace_id, opts) do
    Webhook
    |> where([w], w.workspace_id == ^workspace_id)
    |> maybe_filter(opts)
    |> Pagination.paginate(opts)
  end

  @impl true
  def increment_trigger_count(id) do
    now = DateTime.utc_now()

    Webhook
    |> where([w], w.id == ^id)
    |> Repo.update_all(inc: [trigger_count: 1], set: [last_triggered_at: now])

    :ok
  end

  defp maybe_filter(query, opts) do
    Enum.reduce(opts, query, fn
      {:target_type, type}, q when not is_nil(type) ->
        where(q, [w], w.target_type == ^type)

      {:enabled, enabled}, q when is_boolean(enabled) ->
        where(q, [w], w.enabled == ^enabled)

      _, q ->
        q
    end)
  end
end
