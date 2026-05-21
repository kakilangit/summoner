defmodule SummonerWeb.PipelineLive.Show do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Ports.Events
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Pipelines
  alias Summoner.Ports.Workers
  alias Summoner.Services.TimeZone

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope
    pipeline = Pipelines.get_pipeline!(scope, workspace.id, id)
    runs_page = Pipelines.list_runs_paginated(pipeline.id)

    if connected?(socket) do
      Events.subscribe({:pipeline, workspace.id, pipeline.id})
    end

    socket =
      socket
      |> assign(page_title: pipeline.name)
      |> assign(pipeline: pipeline, runs_page: runs_page)
      |> assign(has_active_run: Pipelines.has_active_run?(pipeline.id))
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Quests", ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/pipelines"},
          {pipeline.name, nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("run", _params, socket) do
    authorize(socket, :operate, fn -> do_run(socket) end)
  end

  @impl true
  def handle_event("cancel_run", %{"run_id" => run_id}, socket) do
    authorize(socket, :operate, fn ->
      case Pipelines.cancel_run(run_id) do
        {:ok, _run} ->
          runs_page =
            Pipelines.list_runs_paginated(socket.assigns.pipeline.id,
              page: socket.assigns.runs_page.page
            )

          {:noreply, socket |> assign(runs_page: runs_page) |> put_flash(:info, "Run cancelled.")}

        {:error, :already_terminal} ->
          {:noreply, put_flash(socket, :info, "Run already finished.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not cancel run.")}
      end
    end)
  end

  @impl true
  def handle_event("delete_run", %{"run_id" => run_id}, socket) do
    case Pipelines.delete_run(run_id) do
      {:ok, _run} ->
        runs_page =
          Pipelines.list_runs_paginated(socket.assigns.pipeline.id,
            page: socket.assigns.runs_page.page
          )

        {:noreply, socket |> assign(runs_page: runs_page) |> put_flash(:info, "Run deleted.")}

      {:error, :still_running} ->
        {:noreply, put_flash(socket, :error, "Cannot delete a running run.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete run.")}
    end
  end

  @impl true
  def handle_event("paginate", %{"page" => page_num}, socket) do
    runs_page =
      Pipelines.list_runs_paginated(socket.assigns.pipeline.id, page: String.to_integer(page_num))

    {:noreply, assign(socket, runs_page: runs_page)}
  end

  @impl true
  def handle_event("change_model", %{"agent_id" => agent_id, "model" => model}, socket) do
    scope = socket.assigns.current_scope
    pipeline = socket.assigns.pipeline

    case Enum.find(pipeline.stages, &(&1.agent.id == agent_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Summon not found in quest.")}

      stage ->
        switch_stage_model(socket, scope, pipeline, stage, model)
    end
  end

  # PubSub handlers — refresh runs on any status change
  @impl true
  def handle_info(%Summoner.Domain.Events.PipelineRunStatus{}, socket) do
    pipeline_id = socket.assigns.pipeline.id

    runs_page =
      Pipelines.list_runs_paginated(pipeline_id,
        page: socket.assigns.runs_page.page
      )

    {:noreply,
     socket
     |> assign(runs_page: runs_page)
     |> assign(has_active_run: Pipelines.has_active_run?(pipeline_id))}
  end

  @impl true
  def handle_info(%Summoner.Domain.Events.PipelineStageStatus{}, socket) do
    runs_page =
      Pipelines.list_runs_paginated(socket.assigns.pipeline.id,
        page: socket.assigns.runs_page.page
      )

    {:noreply, assign(socket, runs_page: runs_page)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp do_run(socket) do
    pipeline = socket.assigns.pipeline
    workspace = socket.assigns.workspace

    if Pipelines.has_active_run?(pipeline.id) do
      {:noreply, put_flash(socket, :error, "A run is already running.")}
    else
      case Workers.enqueue_pipeline_run(%{
             pipeline_id: pipeline.id,
             workspace_id: workspace.id,
             input: ""
           }) do
        {:ok, _job} ->
          {:noreply,
           socket
           |> assign(has_active_run: true)
           |> put_flash(:info, "Run enqueued.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not enqueue run.")}
      end
    end
  end

  defp switch_stage_model(socket, scope, pipeline, stage, model) do
    case Agents.update_agent(scope, stage.agent, %{model: model}) do
      {:ok, updated_agent} ->
        updated_agent = Agents.preload_agent(updated_agent)
        pipeline = replace_stage_agent(pipeline, stage.id, updated_agent)

        {:noreply,
         socket
         |> assign(pipeline: pipeline)
         |> put_flash(
           :info,
           "Spirit switched to #{SummonerWeb.CoreComponents.short_model_name(model)}"
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not switch spirit.")}
    end
  end

  defp replace_stage_agent(pipeline, stage_id, agent) do
    stages =
      Enum.map(pipeline.stages, fn s ->
        if s.id == stage_id, do: %{s | agent: agent}, else: s
      end)

    %{pipeline | stages: stages}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">{@pipeline.name}</h1>
          <div class="flex items-center gap-2 mt-1">
            <span class={[
              "badge badge-sm",
              @pipeline.mode == :simple && "badge-ghost",
              @pipeline.mode == :orchestrated && "badge-primary"
            ]}>
              {@pipeline.mode}
            </span>
            <span class={[
              "badge badge-sm",
              @pipeline.trigger_type == :manual && "badge-ghost",
              @pipeline.trigger_type == :scheduled && "badge-info"
            ]}>
              {@pipeline.trigger_type}
            </span>
            <span :if={@pipeline.cron_expression} class="text-sm text-base-content/60">
              {Summoner.Domain.Types.CronBuilder.to_human(@pipeline.cron_expression)}
            </span>
          </div>
        </div>
        <div class="flex gap-2">
          <button
            :if={@pipeline.stages != [] && !@has_active_run && @can?.(:operate)}
            phx-click={show_confirm("#run-pipeline-show")}
            class="btn btn-success btn-sm"
          >
            Cast Now
          </button>
          <button
            :if={@pipeline.stages != [] && @has_active_run && @can?.(:operate)}
            class="btn btn-success btn-sm btn-disabled"
            disabled
          >
            Run...
          </button>
          <.confirm_modal
            :if={@pipeline.stages != [] && @can?.(:operate)}
            id="run-pipeline-show"
            title="Cast quest?"
            message="This will start executing the quest phases sequentially."
            confirm_text="Cast Now"
            variant="warning"
            on_confirm={JS.push("run")}
          />
          <.link
            :if={@can?.(:configure)}
            navigate={
              ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/pipelines/#{@pipeline.id}/edit"
            }
            class="btn btn-ghost btn-sm"
          >
            Edit
          </.link>
        </div>
      </div>

      <div class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title text-lg">Phases</h2>
          <div :if={@pipeline.stages == []} class="text-base-content/60">
            No phases configured.
          </div>
          <div class="space-y-2">
            <div
              :for={stage <- Enum.sort_by(@pipeline.stages, & &1.position)}
              class="flex items-center gap-3 p-3 bg-base-100 rounded-lg"
            >
              <span class="badge badge-neutral badge-sm font-mono">#{stage.position + 1}</span>
              <span class="font-medium text-sm">{stage.agent.name}</span>
              <.model_switcher agent={stage.agent} id={"stage-model-#{stage.id}"} />
              <span
                :if={stage.depends_on_positions != [] && stage.depends_on_positions != nil}
                class="text-xs text-base-content/40"
              >
                after {Enum.map_join(stage.depends_on_positions, ", ", &"##{&1 + 1}")}
              </span>
              <span
                :if={stage.instruction}
                class="text-xs text-base-content/50 truncate max-w-md ml-auto"
              >
                {stage.instruction}
              </span>
            </div>
          </div>
        </div>
      </div>

      <div>
        <h2 class="text-lg font-bold mb-3">Run History</h2>
        <div :if={@runs_page.entries == []} class="text-center py-8 text-base-content/60">
          No runs yet.
        </div>
        <div class="overflow-x-auto">
          <table :if={@runs_page.entries != []} class="table table-sm">
            <thead>
              <tr>
                <th>Started</th>
                <th>Status</th>
                <th>Duration</th>
                <th>Error</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={run <- @runs_page.entries}>
                <td class="text-sm">
                  <.link
                    navigate={
                      ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/pipelines/#{@pipeline.id}/runs/#{run.id}"
                    }
                    class="link link-hover"
                  >
                    {format_datetime(run.started_at)}
                  </.link>
                </td>
                <td>
                  <span class={run_status_badge(run.status)}>
                    {run.status}
                  </span>
                </td>
                <td class="text-sm">{format_duration(run.started_at, run.completed_at)}</td>
                <td class="text-sm text-error max-w-xs truncate">{run.error}</td>
                <td class="flex gap-1">
                  <button
                    :if={run.status in [:completed, :failed, :cancelled]}
                    phx-click={show_confirm("#delete-run-#{run.id}")}
                    class="btn btn-error btn-xs btn-outline"
                  >
                    Delete
                  </button>
                  <.confirm_modal
                    :if={run.status in [:completed, :failed, :cancelled]}
                    id={"delete-run-#{run.id}"}
                    title="Delete this run?"
                    message="This run record will be permanently removed."
                    confirm_text="Delete Run"
                    variant="error"
                    on_confirm={JS.push("delete_run", value: %{run_id: run.id})}
                  />
                  <button
                    :if={run.status == :running && @can?.(:operate)}
                    phx-click={show_confirm("#cancel-run-show-#{run.id}")}
                    class="btn btn-warning btn-xs btn-outline"
                  >
                    Cancel
                  </button>
                  <.confirm_modal
                    :if={run.status == :running && @can?.(:operate)}
                    id={"cancel-run-show-#{run.id}"}
                    title="Cancel this run?"
                    message="The running quest will be stopped."
                    confirm_text="Cancel Run"
                    variant="warning"
                    on_confirm={JS.push("cancel_run", value: %{run_id: run.id})}
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.pagination page={@runs_page} />
      </div>
    </div>
    """
  end

  defp run_status_badge(:completed), do: "badge badge-success badge-sm"
  defp run_status_badge(:failed), do: "badge badge-error badge-sm"
  defp run_status_badge(:running), do: "badge badge-info badge-sm"
  defp run_status_badge(:cancelled), do: "badge badge-warning badge-sm"
  defp run_status_badge(_), do: "badge badge-ghost badge-sm"

  defp format_datetime(nil), do: "-"

  defp format_datetime(dt) do
    TimeZone.format(dt, format: "%Y-%m-%d %H:%M:%S")
  end

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
