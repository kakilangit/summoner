defmodule SummonerWeb.PluginLive.Show do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Services.Plugins

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workspace = socket.assigns.workspace
    plugin = Plugins.get_plugin!(workspace.id, id)

    socket =
      socket
      |> assign(
        page_title: "#{plugin.name} - Grimoire",
        plugin: plugin,
        logs: nil,
        show_logs: false
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Grimoires", ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/plugins"},
          {plugin.name, nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("enable", _params, socket) do
    authorize(socket, :configure, fn ->
      %{workspace: workspace, plugin: plugin} = socket.assigns

      case Plugins.enable(workspace.id, plugin.id) do
        {:ok, plugin} ->
          {:noreply, socket |> assign(plugin: plugin) |> put_flash(:info, "Grimoire enabled.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Enable failed: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def handle_event("disable", _params, socket) do
    authorize(socket, :configure, fn ->
      %{workspace: workspace, plugin: plugin} = socket.assigns

      case Plugins.disable(workspace.id, plugin.id) do
        {:ok, plugin} ->
          {:noreply, socket |> assign(plugin: plugin) |> put_flash(:info, "Grimoire disabled.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Disable failed: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def handle_event("show_logs", _params, socket) do
    %{workspace: workspace, plugin: plugin} = socket.assigns

    logs =
      case Plugins.get_logs(workspace.id, plugin.id, tail: 200) do
        {:ok, content} -> content
        {:error, _} -> "No logs available."
      end

    {:noreply, assign(socket, logs: logs, show_logs: true)}
  end

  @impl true
  def handle_event("hide_logs", _params, socket) do
    {:noreply, assign(socket, show_logs: false)}
  end

  @impl true
  def handle_event("uninstall", _params, socket) do
    authorize(socket, :configure, fn ->
      %{workspace: workspace, plugin: plugin} = socket.assigns

      case Plugins.uninstall(workspace.id, plugin.id) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Grimoire uninstalled.")
           |> push_navigate(
             to: ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/plugins"
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Uninstall failed: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">{@plugin.name}</h1>
          <p class="text-sm text-base-content/60">v{@plugin.version}</p>
        </div>
        <div :if={@can?.(:configure)} class="flex gap-2">
          <button
            :if={@plugin.status in [:installed, :disabled, :error]}
            phx-click="enable"
            class="btn btn-success btn-sm"
          >
            Enable
          </button>
          <button
            :if={@plugin.status == :enabled}
            phx-click="disable"
            class="btn btn-warning btn-sm"
          >
            Disable
          </button>
          <button
            phx-click={show_confirm("#uninstall-plugin")}
            class="btn btn-error btn-sm btn-outline"
          >
            Uninstall
          </button>
          <.confirm_modal
            id="uninstall-plugin"
            title="Uninstall grimoire?"
            message={"#{@plugin.name} will be permanently removed."}
            confirm_text="Uninstall"
            on_confirm={JS.push("uninstall")}
          />
        </div>
      </div>

      <%!-- Status card --%>
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h2 class="card-title text-lg">Status</h2>
          <div class="flex items-center gap-3">
            <span class={["badge", status_badge_class(@plugin.status)]}>
              {@plugin.status}
            </span>
            <span :if={@plugin.error_message} class="text-sm text-error">
              {@plugin.error_message}
            </span>
          </div>
        </div>
      </div>

      <%!-- Capabilities --%>
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h2 class="card-title text-lg">Capabilities</h2>
          <div class="flex flex-wrap gap-2">
            <span :for={cap <- @plugin.capabilities} class="badge badge-outline badge-lg">
              {cap}
            </span>
          </div>
        </div>
      </div>

      <%!-- Configuration --%>
      <div :if={@plugin.config != %{}} class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h2 class="card-title text-lg">Configuration</h2>
          <pre class="text-sm bg-base-300 p-4 rounded-lg overflow-x-auto"><code>{Jason.encode!(@plugin.config, pretty: true)}</code></pre>
        </div>
      </div>

      <%!-- Manifest --%>
      <div class="collapse collapse-arrow bg-base-200">
        <input type="checkbox" />
        <div class="collapse-title font-medium">Manifest</div>
        <div class="collapse-content">
          <pre class="text-sm bg-base-300 p-4 rounded-lg overflow-x-auto"><code>{Jason.encode!(@plugin.manifest, pretty: true)}</code></pre>
        </div>
      </div>

      <%!-- Logs --%>
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <div class="flex items-center justify-between">
            <h2 class="card-title text-lg">Logs</h2>
            <button
              :if={!@show_logs}
              phx-click="show_logs"
              class="btn btn-ghost btn-sm"
            >
              Show Logs
            </button>
            <button
              :if={@show_logs}
              phx-click="hide_logs"
              class="btn btn-ghost btn-sm"
            >
              Hide Logs
            </button>
          </div>
          <pre
            :if={@show_logs}
            class="text-xs bg-base-300 p-4 rounded-lg overflow-x-auto max-h-96 overflow-y-auto font-mono whitespace-pre-wrap"
          ><code>{@logs}</code></pre>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge_class(:enabled), do: "badge-success"
  defp status_badge_class(:disabled), do: "badge-warning"
  defp status_badge_class(:error), do: "badge-error"
  defp status_badge_class(_), do: "badge-info"
end
