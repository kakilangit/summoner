defmodule Summoner.EventLog do
  @moduledoc """
  In-memory ring buffer for agent activity events.

  Captures recent agent events (invocation start/complete/fail,
  tool calls, swarm turns) for real-time observability without
  database overhead. Events are ephemeral — they survive process
  restarts but not node restarts.

  ## Usage

      EventLog.append(:invocation_started, %{agent_id: "abc", invocation_id: "xyz"})
      EventLog.recent()          # last 500 events
      EventLog.recent(50)        # last 50 events
      EventLog.recent_for(:agent_id, "abc")  # filtered
  """

  use GenServer

  @max_events 500

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Appends an event to the log.

  `type` is an atom (e.g. `:invocation_started`, `:tool_called`).
  `payload` is a map with event details.
  """
  def append(type, payload, name \\ __MODULE__) when is_atom(type) and is_map(payload) do
    GenServer.cast(name, {:append, type, payload})
  end

  @doc """
  Returns the most recent events (newest first).
  """
  def recent(limit \\ @max_events, name \\ __MODULE__) do
    GenServer.call(name, {:recent, limit})
  end

  @doc """
  Returns recent events filtered by a key-value match in the payload.
  """
  def recent_for(key, value, limit \\ @max_events, name \\ __MODULE__) do
    GenServer.call(name, {:recent_for, key, value, limit})
  end

  @doc """
  Clears all events from the log.
  """
  def clear(name \\ __MODULE__) do
    GenServer.cast(name, :clear)
  end

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(_opts) do
    {:ok, %{events: :queue.new(), count: 0}}
  end

  @impl true
  def handle_cast({:append, type, payload}, state) do
    event = %{
      type: type,
      payload: payload,
      timestamp: DateTime.utc_now()
    }

    events = :queue.in(event, state.events)
    count = state.count + 1

    {events, count} =
      if count > @max_events do
        {{:value, _}, events} = :queue.out(events)
        {events, count - 1}
      else
        {events, count}
      end

    {:noreply, %{state | events: events, count: count}}
  end

  def handle_cast(:clear, _state) do
    {:noreply, %{events: :queue.new(), count: 0}}
  end

  @impl true
  def handle_call({:recent, limit}, _from, state) do
    result =
      state.events
      |> :queue.to_list()
      |> Enum.reverse()
      |> Enum.take(limit)

    {:reply, result, state}
  end

  def handle_call({:recent_for, key, value, limit}, _from, state) do
    result =
      state.events
      |> :queue.to_list()
      |> Enum.reverse()
      |> Enum.filter(fn event -> Map.get(event.payload, key) == value end)
      |> Enum.take(limit)

    {:reply, result, state}
  end
end
