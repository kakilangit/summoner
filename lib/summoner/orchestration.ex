defmodule Summoner.Orchestration do
  @moduledoc """
  The Orchestration context.

  Manages invocations, steps, and events — the lifecycle of agent work.
  """

  import Ecto.Query, warn: false

  alias Summoner.Events
  alias Summoner.Events.{InvocationCompleted, InvocationFailed, InvocationStarted}
  alias Summoner.Orchestration.{Invocation, InvocationEvent, InvocationStep, Subtask}
  alias Summoner.Repo
  alias Summoner.Workspaces

  # -------------------------------------------------------------------
  # Invocations
  # -------------------------------------------------------------------

  @doc """
  Creates an invocation.
  """
  def create_invocation(%{user: _user}, attrs) do
    %Invocation{}
    |> Invocation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets an invocation scoped to a workspace.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_invocation!(%{user: _user}, workspace_id, invocation_id) do
    Invocation
    |> Workspaces.where_workspace(workspace_id)
    |> Repo.get!(invocation_id)
  end

  @doc """
  Lists invocations for a workspace, most recent first.

  Options:
  - `:status` — filter by status
  - `:agent_id` — filter by agent
  - `:conversation_id` — filter by conversation
  - `:limit` — max results (default 50)
  """
  def list_invocations(%{user: _user}, workspace_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Invocation
    |> Workspaces.where_workspace(workspace_id)
    |> maybe_filter(:status, Keyword.get(opts, :status))
    |> maybe_filter(:agent_id, Keyword.get(opts, :agent_id))
    |> maybe_filter(:conversation_id, Keyword.get(opts, :conversation_id))
    |> order_by([i], desc: i.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists invocations currently running for a specific agent.

  Used by ProcessMonitor to mark in-flight invocations as failed
  when an AgentServer crashes.
  """
  def list_running_invocations(agent_id) do
    Invocation
    |> where([i], i.agent_id == ^agent_id)
    |> where([i], i.status in [:queued, :running])
    |> Repo.all()
  end

  @doc """
  Transitions an invocation to a new status.

  Accepts optional fields: `end_reason`, `output`, `started_at`, `completed_at`.
  """
  def update_invocation_status(%Invocation{} = invocation, status, attrs \\ %{}) do
    attrs = Map.put(attrs, :status, status)

    with {:ok, updated} <-
           invocation
           |> Invocation.status_changeset(attrs)
           |> Repo.update() do
      publish_invocation_event(updated, status, attrs)
      {:ok, updated}
    end
  end

  @doc """
  Updates invocation status by ID (without preloading the full struct).
  Used for cancellation when we only have the ID.
  """
  def update_invocation_status_by_id(invocation_id, status, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    completed_at = Map.get(attrs, :completed_at, now)
    end_reason = Map.get(attrs, :end_reason, :cancelled)

    Invocation
    |> where([i], i.id == ^invocation_id and i.status == :running)
    |> Repo.update_all(set: [status: status, end_reason: end_reason, completed_at: completed_at])
  end

  defp publish_invocation_event(invocation, status, attrs) do
    base = %{
      workspace_id: invocation.workspace_id,
      agent_id: invocation.agent_id,
      invocation_id: invocation.id
    }

    event =
      case status do
        :running ->
          struct!(InvocationStarted, base)

        :completed ->
          struct!(InvocationCompleted, Map.put(base, :output, Map.get(attrs, :output)))

        status when status in [:failed, :cancelled] ->
          struct!(InvocationFailed, Map.put(base, :output, Map.get(attrs, :output)))

        _other ->
          nil
      end

    if event, do: Events.publish(event)
  end

  # -------------------------------------------------------------------
  # Steps
  # -------------------------------------------------------------------

  @doc """
  Adds a step to an invocation.
  """
  def add_step(attrs) do
    %InvocationStep{}
    |> InvocationStep.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists steps for an invocation, ordered by step number.
  """
  def list_steps(invocation_id) do
    InvocationStep
    |> where([s], s.invocation_id == ^invocation_id)
    |> order_by([s], asc: s.step_number)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Events
  # -------------------------------------------------------------------

  @doc """
  Adds an event to an invocation.
  """
  def add_event(attrs) do
    workspace_id = Map.get(attrs, :workspace_id) || Map.get(attrs, "workspace_id")

    with {:ok, event} <-
           %InvocationEvent{}
           |> InvocationEvent.changeset(attrs)
           |> Repo.insert() do
      if workspace_id do
        Events.publish(%Events.InvocationEvent{
          workspace_id: workspace_id,
          agent_id: event.agent_id,
          invocation_id: event.invocation_id,
          event: event
        })
      end

      {:ok, event}
    end
  end

  @doc """
  Lists events for an invocation, ordered chronologically.

  Options:
  - `:visibility` — filter by visibility (`:public` or `:internal`)
  """
  def list_events(invocation_id, opts \\ []) do
    visibility = Keyword.get(opts, :visibility)

    InvocationEvent
    |> where([e], e.invocation_id == ^invocation_id)
    |> maybe_filter(:visibility, visibility)
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Subtasks
  # -------------------------------------------------------------------

  @doc """
  Batch-creates subtasks for a manager invocation in a single transaction.

  Each entry in `subtask_attrs_list` must include `:description` and `:position`.
  The `:invocation_id` is set from the given invocation.

  Returns `{:ok, [subtask]}` or `{:error, changeset}`.
  """
  def create_subtasks(%Invocation{} = invocation, subtask_attrs_list)
      when is_list(subtask_attrs_list) do
    Repo.transaction(fn ->
      Enum.map(subtask_attrs_list, &insert_subtask!(invocation.id, &1))
    end)
  end

  defp insert_subtask!(invocation_id, attrs) do
    attrs = Map.put(attrs, :invocation_id, invocation_id)

    case %Subtask{} |> Subtask.changeset(attrs) |> Repo.insert() do
      {:ok, subtask} -> subtask
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  Atomically claims a subtask for a worker agent.

  Only claims if the subtask is currently `pending`. Uses optimistic
  locking via status check. Returns `{:ok, subtask}` or `{:error, :already_claimed}`.
  """
  def claim_subtask(subtask_id, agent_id, worker_invocation_id) do
    Repo.transaction(fn ->
      subtask = lock_pending_subtask(subtask_id)
      do_claim_subtask(subtask, agent_id, worker_invocation_id)
    end)
  end

  defp lock_pending_subtask(subtask_id) do
    Subtask
    |> where([s], s.id == ^subtask_id and s.status == :pending)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp do_claim_subtask(nil, _agent_id, _worker_invocation_id) do
    Repo.rollback(:already_claimed)
  end

  defp do_claim_subtask(subtask, agent_id, worker_invocation_id) do
    case subtask
         |> Subtask.claim_changeset(%{
           status: :running,
           assigned_agent_id: agent_id,
           worker_invocation_id: worker_invocation_id
         })
         |> Repo.update() do
      {:ok, claimed} -> claimed
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  Transitions a subtask to `completed`.
  """
  def complete_subtask(%Subtask{} = subtask) do
    subtask
    |> Subtask.status_changeset(%{status: :completed})
    |> Repo.update()
  end

  @doc """
  Transitions a subtask to `failed`, incrementing retry_count.
  """
  def fail_subtask(%Subtask{} = subtask) do
    subtask
    |> Subtask.status_changeset(%{status: :failed, retry_count: subtask.retry_count + 1})
    |> Repo.update()
  end

  @doc """
  Transitions a subtask to `skipped`.
  """
  def skip_subtask(%Subtask{} = subtask) do
    subtask
    |> Subtask.status_changeset(%{status: :skipped})
    |> Repo.update()
  end

  @doc """
  Transitions a subtask to `running`.
  """
  def start_subtask(%Subtask{} = subtask) do
    subtask
    |> Subtask.status_changeset(%{status: :running})
    |> Repo.update()
  end

  @doc """
  Requeues a subtask back to `pending` (for reaper use), incrementing retry_count.
  """
  def requeue_subtask(%Subtask{} = subtask) do
    subtask
    |> Subtask.status_changeset(%{status: :pending, retry_count: subtask.retry_count + 1})
    |> Repo.update()
  end

  @doc """
  Returns subtasks for an invocation whose dependencies are all met
  (all `depends_on_ids` are in a terminal state: completed, failed, or skipped).

  Only returns subtasks in `pending` status.
  """
  def ready_subtasks(invocation_id) do
    all_subtasks = list_subtasks(invocation_id)

    failed_ids =
      all_subtasks
      |> Enum.filter(&(&1.status in [:failed, :skipped]))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    terminal_ids =
      all_subtasks
      |> Enum.filter(&(&1.status in [:completed, :failed, :skipped]))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    # Skip pending subtasks that depend on any failed/skipped dependency
    all_subtasks
    |> Enum.filter(fn subtask ->
      subtask.status == :pending &&
        Enum.any?(subtask.depends_on_ids, &MapSet.member?(failed_ids, &1))
    end)
    |> Enum.each(&skip_subtask/1)

    # Return subtasks whose deps are all terminal and all succeeded
    all_subtasks
    |> Enum.filter(fn subtask ->
      subtask.status == :pending &&
        Enum.all?(subtask.depends_on_ids, &MapSet.member?(terminal_ids, &1)) &&
        not Enum.any?(subtask.depends_on_ids, &MapSet.member?(failed_ids, &1))
    end)
  end

  @doc """
  Lists all subtasks for an invocation, ordered by position.
  """
  def list_subtasks(invocation_id) do
    Subtask
    |> where([s], s.invocation_id == ^invocation_id)
    |> order_by([s], asc: s.position)
    |> Repo.all()
  end

  @doc """
  Gets a subtask by ID. Returns `nil` if not found.
  """
  def get_subtask(subtask_id) do
    Repo.get(Subtask, subtask_id)
  end

  # -------------------------------------------------------------------
  # Internal API (for infrastructure use)
  # -------------------------------------------------------------------

  @doc """
  Gets an invocation by ID without workspace scoping.

  Intended for infrastructure use (e.g. GenServer crash recovery).
  """
  def get_invocation_by_id(invocation_id) do
    Repo.get(Invocation, invocation_id)
  end

  @doc """
  Atomically dequeues the oldest queued invocation for an agent.

  Uses `FOR UPDATE SKIP LOCKED` to avoid contention. Returns the
  invocation or `nil` if none are queued.
  """
  def dequeue_invocation(agent_id) do
    Invocation
    |> where([i], i.agent_id == ^agent_id and i.status == :queued)
    |> order_by([i], asc: i.inserted_at)
    |> limit(1)
    |> lock("FOR UPDATE SKIP LOCKED")
    |> Repo.one()
  end

  @doc """
  Cancels all queued invocations for a given conversation.

  Used to clean up stale queued invocations when a swarm run ends,
  preventing them from being dequeued and executed later.

  Returns `{count, nil}` with the number of cancelled invocations.
  """
  def cancel_queued_invocations_for_conversation(conversation_id) do
    Invocation
    |> where([i], i.conversation_id == ^conversation_id and i.status == :queued)
    |> Repo.update_all(set: [status: :cancelled, completed_at: DateTime.utc_now()])
  end

  @doc """
  Returns IDs of running invocations for a given agent and conversation.
  """
  def running_invocation_ids(agent_id, conversation_id) do
    Invocation
    |> where([i], i.agent_id == ^agent_id and i.conversation_id == ^conversation_id)
    |> where([i], i.status == :running)
    |> select([i], i.id)
    |> Repo.all()
  end

  @doc """
  Returns `true` if the conversation has any running or queued invocations.
  """
  def conversation_active?(conversation_id) do
    Invocation
    |> where([i], i.conversation_id == ^conversation_id)
    |> where([i], i.status in [:running, :queued])
    |> limit(1)
    |> Repo.exists?()
  end

  # -------------------------------------------------------------------
  # Internal
  # -------------------------------------------------------------------

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value) do
    where(query, [q], field(q, ^field) == ^value)
  end
end
