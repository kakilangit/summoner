defmodule Summoner.Adapters.Persistence.Audit do
  @moduledoc """
  The Audit context.

  Provides compliance logging for significant actions across the system.
  All entries are workspace-scoped and append-only.
  """

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Workspaces
  alias Summoner.Domain.Schemas.AuditLog
  alias Summoner.Repo

  @behaviour Summoner.Ports.Persistence.Audit.Adapter

  @doc """
  Logs an audit entry.

  ## Examples

      Audit.log(%{
        workspace_id: workspace.id,
        user_id: user.id,
        action: "quota_exceeded",
        detail: %{usage: 52_000, quota: 50_000}
      })

  """
  def log(attrs) do
    %AuditLog{}
    |> AuditLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists audit logs for a workspace, most recent first.

  Options:
  - `:action` — filter by action string
  - `:user_id` — filter by user
  - `:agent_id` — filter by agent
  - `:limit` — max results (default 50)
  - `:offset` — pagination offset (default 0)
  """
  def list_logs(workspace_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    AuditLog
    |> Workspaces.where_workspace(workspace_id)
    |> maybe_filter(:action, Keyword.get(opts, :action))
    |> maybe_filter(:user_id, Keyword.get(opts, :user_id))
    |> maybe_filter(:agent_id, Keyword.get(opts, :agent_id))
    |> order_by([l], desc: l.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value) do
    where(query, [q], field(q, ^field) == ^value)
  end
end
