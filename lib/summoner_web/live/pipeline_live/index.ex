defmodule SummonerWeb.PipelineLive.Index do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Ports.Events
  alias Summoner.Ports.Persistence.Pipelines
  alias Summoner.Ports.Workers

  @sort_options [
    {"Name", :name},
    {"Mode", :mode},
    {"Trigger", :trigger_type},
    {"Created", :inserted_at}
  ]
  @default_sort_by :name
  @default_sort_dir :asc
  @filter_fields [:name]

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Quests - #{workspace.name}",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Quests", nil}
        ]
      )
      |> load_page()

    if connected?(socket) do
      Enum.each(socket.assigns.page.entries, fn p ->
        Events.subscribe({:pipeline, workspace.id, p.id})
      end)
    end

    {:ok, socket}
  end

  @impl true
  def handle_event("paginate", %{"page" => page_num}, socket) do
    {:noreply, socket |> assign(page_num: String.to_integer(page_num)) |> load_page()}
  end

  @impl true
  def handle_event("sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)

    sort_dir =
      if socket.assigns.sort_by == field,
        do: toggle_dir(socket.assigns.sort_dir),
        else: :asc

    {:noreply, socket |> assign(sort_by: field, sort_dir: sort_dir) |> load_page()}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, socket |> assign(filter: filter) |> load_page()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    authorize(socket, :configure, fn ->
      scope = socket.assigns.current_scope
      workspace = socket.assigns.workspace
      pipeline = Pipelines.get_pipeline!(scope, workspace.id, id)

      case Pipelines.delete_pipeline(scope, pipeline) do
        {:ok, _} ->
          {:noreply,
           socket
           |> load_page()
           |> put_flash(:info, "Quest deleted.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete quest.")}
      end
    end)
  end

  @impl true
  def handle_event("run", %{"id" => id}, socket) do
    authorize(socket, :operate, fn ->
      workspace = socket.assigns.workspace

      case Workers.enqueue_pipeline_run(%{
             pipeline_id: id,
             workspace_id: workspace.id,
             input: ""
           }) do
        {:ok, _job} ->
          {:noreply, put_flash(socket, :info, "Run enqueued.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not enqueue run.")}
      end
    end)
  end

  @impl true
  def handle_event("cancel_run", %{"run_id" => run_id}, socket) do
    authorize(socket, :operate, fn ->
      case Pipelines.cancel_run(run_id) do
        {:ok, _} ->
          latest_runs = load_latest_runs(socket.assigns.page.entries)

          {:noreply,
           socket |> assign(latest_runs: latest_runs) |> put_flash(:info, "Run cancelled.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not cancel run.")}
      end
    end)
  end

  # PubSub — refresh latest runs on status changes
  @impl true
  def handle_info(%Summoner.Domain.Events.PipelineRunStatus{}, socket) do
    latest_runs = load_latest_runs(socket.assigns.page.entries)
    {:noreply, assign(socket, latest_runs: latest_runs)}
  end

  @impl true
  def handle_info(%Summoner.Domain.Events.PipelineStageStatus{}, socket) do
    latest_runs = load_latest_runs(socket.assigns.page.entries)
    {:noreply, assign(socket, latest_runs: latest_runs)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_page(socket) do
    %{current_scope: scope, workspace: workspace} = socket.assigns
    opts = list_opts(socket.assigns)
    page = Pipelines.list_pipelines_paginated(scope, workspace.id, opts)
    latest_runs = load_latest_runs(page.entries)
    assign(socket, page: page, latest_runs: latest_runs)
  end

  defp list_opts(assigns) do
    [
      page: Map.get(assigns, :page_num, assigns[:page] && assigns.page.page) || 1,
      sort_by: assigns.sort_by,
      sort_dir: assigns.sort_dir,
      filter: assigns.filter,
      filter_fields: @filter_fields
    ]
  end

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  defp load_latest_runs(pipelines) do
    Map.new(pipelines, fn p -> {p.id, Pipelines.latest_run(p.id)} end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Quests</h1>
        <.link
          :if={@can?.(:configure)}
          navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/quests/new"}
          class="btn btn-primary btn-sm"
        >
          New Quest
        </.link>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search quests..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>No quests yet. Create one to chain summons together.</p>
        <p :if={@filter != ""}>No quests match your search.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={pipeline <- @page.entries}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div>
            <div class="flex items-center gap-2">
              <.link
                navigate={
                  ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/quests/#{pipeline.id}"
                }
                class="font-medium link link-hover"
              >
                {pipeline.name}
              </.link>
              <span class="text-xs text-base-content/40">
                {pipeline.mode}
              </span>
              <span class="text-xs text-base-content/30">&middot;</span>
              <span class="text-xs text-base-content/40">
                {pipeline.trigger_type}
              </span>
              <.run_status_indicator run={@latest_runs[pipeline.id]} />
            </div>
            <div class="text-sm text-base-content/60">
              {length(pipeline.stages)} phase(s)
              <span :if={pipeline.cron_expression}>
                &middot; {Summoner.Domain.Types.CronBuilder.to_human(pipeline.cron_expression)}
              </span>
              <span :if={@latest_runs[pipeline.id]}>
                &middot; last run {format_relative(@latest_runs[pipeline.id].started_at)}
              </span>
            </div>
          </div>
          <div class="flex gap-2">
            <button
              :if={running?(@latest_runs[pipeline.id]) && @can?.(:operate)}
              phx-click={show_confirm("#cancel-run-#{pipeline.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Cancel
            </button>
            <.confirm_modal
              :if={running?(@latest_runs[pipeline.id]) && @can?.(:operate)}
              id={"cancel-run-#{pipeline.id}"}
              title="Cancel run?"
              message="The currently running quest will be stopped."
              confirm_text="Cancel Run"
              variant="warning"
              on_confirm={
                JS.push("cancel_run",
                  value: %{run_id: @latest_runs[pipeline.id] && @latest_runs[pipeline.id].id}
                )
              }
            />
            <button
              :if={pipeline.stages != [] && !running?(@latest_runs[pipeline.id]) && @can?.(:operate)}
              phx-click={show_confirm("#run-pipeline-#{pipeline.id}")}
              class="btn btn-success btn-sm btn-outline"
            >
              Cast
            </button>
            <.confirm_modal
              :if={pipeline.stages != [] && !running?(@latest_runs[pipeline.id]) && @can?.(:operate)}
              id={"run-pipeline-#{pipeline.id}"}
              title="Cast quest?"
              message="This will start executing the quest phases sequentially."
              confirm_text="Cast Now"
              variant="warning"
              on_confirm={JS.push("run", value: %{id: pipeline.id})}
            />
            <.link
              :if={@can?.(:configure)}
              navigate={
                ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/quests/#{pipeline.id}/edit"
              }
              class="btn btn-ghost btn-sm"
            >
              Edit
            </.link>
            <button
              :if={@can?.(:configure)}
              phx-click={show_confirm("#delete-pipeline-#{pipeline.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Delete
            </button>
            <.confirm_modal
              :if={@can?.(:configure)}
              id={"delete-pipeline-#{pipeline.id}"}
              title="Delete quest?"
              message="This quest, its phases, and all run history will be permanently removed."
              confirm_text="Delete"
              on_confirm={JS.push("delete", value: %{id: pipeline.id})}
            />
          </div>
        </div>
      </div>

      <.pagination page={@page} />
    </div>
    """
  end

  defp running?(nil), do: false
  defp running?(%{status: :running}), do: true
  defp running?(_), do: false

  attr :run, :map, default: nil

  defp run_status_indicator(%{run: nil} = assigns) do
    ~H""
  end

  defp run_status_indicator(%{run: run} = assigns) do
    assigns = assign(assigns, :run, run)

    ~H"""
    <span class={run_status_badge(@run.status)}>
      {@run.status}
    </span>
    """
  end

  defp run_status_badge(:completed), do: "badge badge-success badge-xs"
  defp run_status_badge(:failed), do: "badge badge-error badge-xs"
  defp run_status_badge(:running), do: "badge badge-info badge-xs animate-pulse"
  defp run_status_badge(:cancelled), do: "badge badge-warning badge-xs"
  defp run_status_badge(_), do: "badge badge-ghost badge-xs"

  defp format_relative(nil), do: ""

  defp format_relative(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end
