defmodule SummonerWeb.EventRuleLive.Show do
  use SummonerWeb, :live_view

  alias Summoner.Services.EventRules

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope
    rule = EventRules.get_rule!(scope, workspace.id, id)

    socket =
      socket
      |> assign(
        page_title: "#{rule.name} - #{workspace.name}",
        rule: rule,
        exec_page_num: 1
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Omens", ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/event-rules"},
          {rule.name, nil}
        ]
      )
      |> load_executions()

    {:ok, socket}
  end

  @impl true
  def handle_event("paginate_executions", %{"page" => page_num}, socket) do
    {:noreply, socket |> assign(exec_page_num: String.to_integer(page_num)) |> load_executions()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">{@rule.name}</h1>
        <div class="flex gap-2">
          <.link
            :if={@can?.(:configure)}
            navigate={
              ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/event-rules/#{@rule.id}/edit"
            }
            class="btn btn-ghost btn-sm"
          >
            Edit
          </.link>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div class="p-4 bg-base-200 rounded-lg space-y-3">
          <h2 class="font-semibold">Details</h2>
          <div>
            <span class="text-sm text-base-content/60">Status</span>
            <p>
              <span :if={@rule.enabled} class="badge badge-success badge-sm">Enabled</span>
              <span :if={!@rule.enabled} class="badge badge-neutral badge-sm">Disabled</span>
            </p>
          </div>
          <div :if={@rule.description}>
            <span class="text-sm text-base-content/60">Description</span>
            <p>{@rule.description}</p>
          </div>
          <div>
            <span class="text-sm text-base-content/60">Event Type</span>
            <p><span class="badge badge-ghost badge-sm">{@rule.event_type}</span></p>
          </div>
          <div>
            <span class="text-sm text-base-content/60">Action Type</span>
            <p><span class="badge badge-ghost badge-sm">{@rule.action_type}</span></p>
          </div>
          <div>
            <span class="text-sm text-base-content/60">Priority</span>
            <p>{@rule.priority}</p>
          </div>
          <div>
            <span class="text-sm text-base-content/60">Cooldown</span>
            <p>{@rule.cooldown_s}s</p>
          </div>
          <div>
            <span class="text-sm text-base-content/60">Fire Count</span>
            <p>{@rule.fire_count}</p>
          </div>
          <div :if={@rule.max_fires_per_hour > 0}>
            <span class="text-sm text-base-content/60">Rate Limit</span>
            <p>{@rule.max_fires_per_hour}/hour</p>
          </div>
          <div :if={@rule.consecutive_failures > 0}>
            <span class="text-sm text-base-content/60">Consecutive Failures</span>
            <p class="text-warning">{@rule.consecutive_failures}</p>
          </div>
          <div :if={@rule.disabled_until}>
            <span class="text-sm text-base-content/60">Circuit Disabled Until</span>
            <p class="text-error">{Calendar.strftime(@rule.disabled_until, "%Y-%m-%d %H:%M:%S")}</p>
          </div>
          <div :if={@rule.last_fired_at}>
            <span class="text-sm text-base-content/60">Last Fired</span>
            <p>{Calendar.strftime(@rule.last_fired_at, "%Y-%m-%d %H:%M:%S")}</p>
          </div>
        </div>

        <div class="space-y-4">
          <div class="p-4 bg-base-200 rounded-lg">
            <h2 class="font-semibold mb-2">Conditions</h2>
            <pre class="p-3 bg-base-300 rounded text-sm overflow-x-auto"><code>{Jason.encode!(@rule.conditions, pretty: true)}</code></pre>
          </div>

          <div class="p-4 bg-base-200 rounded-lg">
            <h2 class="font-semibold mb-2">Action Config</h2>
            <pre class="p-3 bg-base-300 rounded text-sm overflow-x-auto"><code>{Jason.encode!(@rule.action_config, pretty: true)}</code></pre>
          </div>
        </div>
      </div>

      <div class="space-y-4">
        <h2 class="text-xl font-semibold">Executions</h2>

        <div :if={@exec_page.entries == []} class="text-center py-8 text-base-content/60">
          <p>No executions yet.</p>
        </div>

        <div class="space-y-2">
          <div
            :for={exec <- @exec_page.entries}
            class="p-4 bg-base-200 rounded-lg"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span class={[
                  "badge badge-sm",
                  exec.status == :fired && "badge-info",
                  exec.status == :succeeded && "badge-success",
                  exec.status == :failed && "badge-error"
                ]}>
                  {exec.status}
                </span>
                <span class="text-sm text-base-content/60">
                  {Calendar.strftime(exec.inserted_at, "%Y-%m-%d %H:%M:%S")}
                </span>
                <span :if={exec.latency_ms} class="text-xs text-base-content/40">
                  {exec.latency_ms}ms
                </span>
              </div>
            </div>
            <div :if={exec.error_reason} class="mt-2 text-sm text-error">
              {exec.error_reason}
            </div>
            <details :if={exec.event_snapshot && exec.event_snapshot != %{}} class="mt-2">
              <summary class="text-sm text-base-content/60 cursor-pointer">Event Snapshot</summary>
              <pre class="mt-1 p-3 bg-base-300 rounded text-xs overflow-x-auto"><code>{Jason.encode!(exec.event_snapshot, pretty: true)}</code></pre>
            </details>
            <details :if={exec.action_result && exec.action_result != %{}} class="mt-2">
              <summary class="text-sm text-base-content/60 cursor-pointer">Action Result</summary>
              <pre class="mt-1 p-3 bg-base-300 rounded text-xs overflow-x-auto"><code>{Jason.encode!(exec.action_result, pretty: true)}</code></pre>
            </details>
          </div>
        </div>

        <.pagination page={@exec_page} event="paginate_executions" />
      </div>
    </div>
    """
  end

  defp load_executions(socket) do
    rule = socket.assigns.rule
    page = EventRules.list_executions_paginated(rule.id, page: socket.assigns.exec_page_num)
    assign(socket, exec_page: page)
  end
end
