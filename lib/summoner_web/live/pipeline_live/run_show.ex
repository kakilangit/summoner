defmodule SummonerWeb.PipelineLive.RunShow do
  use SummonerWeb, :live_view

  alias Summoner.Broadcasts
  alias Summoner.Pipelines

  @refresh_debounce_ms 500

  @impl true
  def mount(%{"id" => pipeline_id, "run_id" => run_id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope
    pipeline = Pipelines.get_pipeline!(scope, workspace.id, pipeline_id)
    run = Pipelines.get_run!(run_id)

    if connected?(socket) do
      Broadcasts.subscribe(Broadcasts.pipeline_topic(workspace.id, pipeline.id))
    end

    socket =
      socket
      |> assign(page_title: "Run - #{pipeline.name}")
      |> assign(pipeline: pipeline, run: run)
      |> assign(stage_instructions: Map.new(pipeline.stages, &{&1.position, &1.instruction}))
      |> assign(stage_events: %{}, subscribed_invocations: MapSet.new())
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Quests", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/quests"},
          {pipeline.name,
           ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/quests/#{pipeline.id}"},
          {"Run", nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("cancel_run", _params, socket) do
    case Pipelines.cancel_run(socket.assigns.run.id) do
      {:ok, _} ->
        run = Pipelines.get_run!(socket.assigns.run.id)
        {:noreply, socket |> assign(run: run) |> put_flash(:info, "Run cancelled.")}

      {:error, :already_terminal} ->
        {:noreply, put_flash(socket, :info, "Run already finished.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not cancel run.")}
    end
  end

  # Stage invocation link — subscribe to invocation events for live feed
  @impl true
  def handle_info({:pipeline_stage_invocation, run_id, position, invocation_id}, socket) do
    if run_id == socket.assigns.run.id do
      {:noreply, subscribe_to_invocation(socket, position, invocation_id)}
    else
      {:noreply, socket}
    end
  end

  # Invocation event — append to the stage's event feed
  @impl true
  def handle_info({:invocation_event, event}, socket) do
    position = Map.get(socket.assigns, :invocation_positions, %{})[event.invocation_id]

    if position do
      events = Map.get(socket.assigns.stage_events, position, [])
      updated = Map.put(socket.assigns.stage_events, position, events ++ [event])
      {:noreply, assign(socket, stage_events: updated)}
    else
      {:noreply, socket}
    end
  end

  # PubSub — debounce rapid status updates into a single refresh
  @impl true
  def handle_info({:pipeline_run_status, run_id, _status}, socket) do
    if run_id == socket.assigns.run.id do
      {:noreply, schedule_refresh(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:pipeline_run_stage_status, run_id, _position, _status}, socket) do
    if run_id == socket.assigns.run.id do
      {:noreply, schedule_refresh(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:refresh_run, socket) do
    run = Pipelines.get_run!(socket.assigns.run.id)
    {:noreply, socket |> assign(run: run, refresh_timer: nil)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp schedule_refresh(socket) do
    existing = Map.get(socket.assigns, :refresh_timer)
    if existing, do: Process.cancel_timer(existing)
    timer = Process.send_after(self(), :refresh_run, @refresh_debounce_ms)
    assign(socket, refresh_timer: timer)
  end

  defp subscribe_to_invocation(socket, position, invocation_id) do
    already = socket.assigns.subscribed_invocations

    if MapSet.member?(already, invocation_id) do
      socket
    else
      workspace_id = socket.assigns.workspace.id
      topic = Broadcasts.invocation_events_topic(workspace_id, invocation_id)
      Broadcasts.subscribe(topic)

      positions = Map.get(socket.assigns, :invocation_positions, %{})

      socket
      |> assign(subscribed_invocations: MapSet.put(already, invocation_id))
      |> assign(invocation_positions: Map.put(positions, invocation_id, position))
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Run</h1>
          <div class="flex items-center gap-2 mt-1">
            <span class={run_status_badge(@run.status)}>
              {@run.status}
            </span>
            <span class="text-sm text-base-content/60">
              {format_datetime(@run.started_at)}
            </span>
            <span :if={@run.completed_at} class="text-sm text-base-content/60">
              ({format_duration(@run.started_at, @run.completed_at)})
            </span>
          </div>
        </div>
        <button
          :if={@run.status == :running}
          phx-click={show_confirm("#cancel-run-detail")}
          class="btn btn-error btn-sm"
        >
          Cancel Run
        </button>
        <.confirm_modal
          :if={@run.status == :running}
          id="cancel-run-detail"
          title="Cancel this run?"
          message="The running quest will be stopped."
          confirm_text="Cancel Run"
          variant="warning"
          on_confirm={JS.push("cancel_run")}
        />
      </div>

      <div :if={@run.input && @run.input != ""} class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title text-sm">Input</h2>
          <pre class="text-sm whitespace-pre-wrap bg-base-100 p-3 rounded-lg">{@run.input}</pre>
        </div>
      </div>

      <div :if={@run.output} class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title text-sm">Output</h2>
          <pre class="text-sm whitespace-pre-wrap bg-base-100 p-3 rounded-lg">{@run.output}</pre>
        </div>
      </div>

      <div :if={@run.error} class="alert alert-error">
        <span class="text-sm">{@run.error}</span>
      </div>

      <div>
        <h2 class="text-lg font-bold mb-3">Phases</h2>
        <div :if={@run.stages == []} class="text-base-content/60">
          No phase data yet.
        </div>
        <div class="space-y-2">
          <div
            :for={stage <- Enum.sort_by(@run.stages, & &1.position)}
            class={[
              "rounded-lg border overflow-hidden",
              stage_card_border(stage.status)
            ]}
          >
            <div class={["px-4 py-3", stage_card_bg(stage.status)]}>
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2.5">
                  <span class="badge badge-neutral badge-sm font-mono">#{stage.position + 1}</span>
                  <div>
                    <span :if={stage.agent} class="font-medium text-sm">{stage.agent.name}</span>
                    <div
                      :if={stage.provider_name || stage.model_name}
                      class="text-xs text-base-content/50 flex items-center gap-1"
                    >
                      <span :if={stage.provider_name}>{stage.provider_name}</span>
                      <span :if={stage.provider_name && stage.model_name}>·</span>
                      <span :if={stage.model_name} class="font-mono">{stage.model_name}</span>
                    </div>
                  </div>
                  <span class={stage_status_badge(stage.status)}>{stage.status}</span>
                </div>
                <span :if={stage.completed_at} class="text-xs text-base-content/50 font-mono">
                  {format_duration(stage.started_at, stage.completed_at)}
                </span>
                <span
                  :if={stage.status == :running && stage.started_at}
                  class="text-xs text-base-content/50 font-mono animate-pulse"
                >
                  running...
                </span>
              </div>

              <%!-- Stage instruction --%>
              <p
                :if={Map.get(@stage_instructions, stage.position)}
                class="text-xs text-base-content/50 mt-1.5 line-clamp-2"
              >
                {Map.get(@stage_instructions, stage.position)}
              </p>

              <%!-- Progress indicator for running stage --%>
              <div :if={stage.status == :running} class="mt-2">
                <progress class="progress progress-info w-full h-1"></progress>
              </div>

              <%!-- Live event feed for running/completed stages --%>
              <.stage_event_feed events={Map.get(@stage_events, stage.position, [])} />
            </div>

            <%!-- Expandable output/error sections --%>
            <div :if={stage.output || stage.error || stage.input} class="border-t border-base-300/30">
              <div :if={stage.input} class="px-4 py-2 border-b border-base-300/20">
                <details>
                  <summary class="text-xs font-medium cursor-pointer text-base-content/60">
                    Input
                  </summary>
                  <pre class="text-xs whitespace-pre-wrap bg-base-100 p-2 rounded mt-1 max-h-40 overflow-y-auto">{stage.input}</pre>
                </details>
              </div>

              <div :if={stage.output} class="px-4 py-2">
                <details open>
                  <summary class="text-xs font-medium cursor-pointer text-base-content/60">
                    Output
                  </summary>
                  <pre class="text-xs whitespace-pre-wrap bg-base-100 p-2 rounded mt-1 max-h-40 overflow-y-auto">{stage.output}</pre>
                </details>
              </div>

              <div :if={stage.error} class="px-4 py-2">
                <div class="text-xs text-error bg-error/10 rounded p-2">
                  {stage.error}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp run_status_badge(:completed), do: "badge badge-success badge-sm"
  defp run_status_badge(:failed), do: "badge badge-error badge-sm"
  defp run_status_badge(:running), do: "badge badge-info badge-sm animate-pulse"
  defp run_status_badge(:cancelled), do: "badge badge-warning badge-sm"
  defp run_status_badge(_), do: "badge badge-ghost badge-sm"

  defp stage_status_badge(:pending), do: "badge badge-ghost badge-xs"
  defp stage_status_badge(:completed), do: "badge badge-success badge-xs"
  defp stage_status_badge(:failed), do: "badge badge-error badge-xs"
  defp stage_status_badge(:running), do: "badge badge-info badge-xs animate-pulse"
  defp stage_status_badge(:skipped), do: "badge badge-warning badge-xs"
  defp stage_status_badge(_), do: "badge badge-ghost badge-xs"

  defp stage_card_border(:running), do: "border-info/40"
  defp stage_card_border(:completed), do: "border-success/30"
  defp stage_card_border(:failed), do: "border-error/30"
  defp stage_card_border(_), do: "border-base-300/50"

  defp stage_card_bg(:running), do: "bg-info/5"
  defp stage_card_bg(:completed), do: "bg-success/5"
  defp stage_card_bg(:failed), do: "bg-error/5"
  defp stage_card_bg(_), do: "bg-base-200"

  defp stage_event_feed(%{events: []} = assigns), do: ~H""

  defp stage_event_feed(assigns) do
    ~H"""
    <div class="mt-2 space-y-0.5 max-h-32 overflow-y-auto text-xs font-mono text-base-content/60">
      <div :for={event <- @events} class="flex items-center gap-1.5 py-0.5">
        <span class={event_icon_class(event.event_type)}>{event_icon(event.event_type)}</span>
        <span class="truncate">{event.summary}</span>
      </div>
    </div>
    """
  end

  defp event_icon(:tool_started), do: "▶"
  defp event_icon(:tool_finished), do: "✓"
  defp event_icon(:tool_failed), do: "✗"
  defp event_icon(:completed), do: "●"
  defp event_icon(:failed), do: "●"
  defp event_icon(_), do: "·"

  defp event_icon_class(:tool_started), do: "text-info"
  defp event_icon_class(:tool_finished), do: "text-success"
  defp event_icon_class(:tool_failed), do: "text-error"
  defp event_icon_class(:completed), do: "text-success"
  defp event_icon_class(:failed), do: "text-error"
  defp event_icon_class(_), do: "text-base-content/40"

  defp format_datetime(nil), do: "-"
  defp format_datetime(dt), do: Summoner.TimeZone.format(dt, format: "%Y-%m-%d %H:%M:%S")

  defp format_duration(nil, _), do: "-"
  defp format_duration(_, nil), do: "-"

  defp format_duration(started, completed) do
    diff = DateTime.diff(completed, started, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m #{rem(diff, 60)}s"
      true -> "#{div(diff, 3600)}h #{div(rem(diff, 3600), 60)}m"
    end
  end
end
