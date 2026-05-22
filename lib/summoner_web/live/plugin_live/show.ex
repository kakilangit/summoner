defmodule SummonerWeb.PluginLive.Show do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Services.Plugins
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Secrets

  @impl true
  def mount(%{"ref" => ref}, _session, socket) do
    workspace = socket.assigns.workspace
    plugin = Plugins.get_plugin_by_ref!(workspace.id, ref)

    config_schema = get_in(plugin.manifest, ["config_schema", "properties"]) || %{}
    required_keys = get_in(plugin.manifest, ["config_schema", "required"]) || []

    # Load secrets (workspace + tenant scoped)
    scope = socket.assigns.current_scope
    secrets = Secrets.list_secrets(scope, workspace.id, workspace.tenant_id)
    secret_options = Enum.map(secrets, &{&1.name, &1.id})

    # Load agents for agent-type config fields
    agents = Agents.list_agents(scope, workspace.id)
    agent_options = Enum.map(agents, &{&1.name, &1.id})

    socket =
      socket
      |> assign(
        page_title: "#{plugin.name} - Grimoire",
        plugin: plugin,
        logs: nil,
        show_logs: false,
        config_form: plugin.config,
        config_schema: config_schema,
        required_keys: required_keys,
        editing_config: false,
        secret_options: secret_options,
        agent_options: agent_options,
        update_available: nil,
        checking_update: true
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Grimoires", ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/plugins"},
          {plugin.name, nil}
        ]
      )

    # Lazy check for updates (async)
    if connected?(socket) do
      send(self(), :check_for_update)
    end

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
  def handle_event("edit_config", _params, socket) do
    {:noreply, assign(socket, editing_config: true)}
  end

  @impl true
  def handle_event("cancel_config", _params, socket) do
    {:noreply, assign(socket, editing_config: false, config_form: socket.assigns.plugin.config)}
  end

  @impl true
  def handle_event("save_config", %{"config" => config_params}, socket) do
    authorize(socket, :configure, fn ->
      %{workspace: workspace, plugin: plugin} = socket.assigns

      # Merge with existing config (keep keys not in form, like empty optional fields)
      new_config =
        config_params
        |> Enum.reject(fn {_k, v} -> v == "" end)
        |> Map.new()

      case Plugins.configure(workspace.id, plugin.id, new_config) do
        {:ok, plugin} ->
          {:noreply,
           socket
           |> assign(plugin: plugin, config_form: plugin.config, editing_config: false)
           |> put_flash(:info, "Configuration saved.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Save failed: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def handle_event("update_plugin", _params, socket) do
    authorize(socket, :configure, fn ->
      %{workspace: workspace, plugin: plugin} = socket.assigns

      case Plugins.update(workspace.id, plugin.id) do
        {:ok, plugin} ->
          {:noreply,
           socket
           |> assign(plugin: plugin, update_available: nil)
           |> put_flash(:info, "Grimoire updated to v#{plugin.version}.")}

        :up_to_date ->
          {:noreply,
           socket
           |> assign(update_available: nil)
           |> put_flash(:info, "Already up to date.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Update failed: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def handle_info(:check_for_update, socket) do
    plugin = socket.assigns.plugin

    result =
      Task.async(fn -> Plugins.check_for_update(plugin) end)
      |> Task.await(30_000)

    case result do
      {:ok, %{version: version}} ->
        {:noreply, assign(socket, checking_update: false, update_available: version)}

      _ ->
        {:noreply, assign(socket, checking_update: false, update_available: nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">{@plugin.name}</h1>
          <p class="text-sm text-base-content/60">v{@plugin.version}</p>
          <p class="text-xs font-mono text-base-content/40">ref: {@plugin.ref}</p>
        </div>
        <div :if={@can?.(:configure)} class="flex gap-2">
          <button
            :if={@update_available}
            phx-click="update_plugin"
            class="btn btn-sm btn-accent"
          >
            Update to v{@update_available}
          </button>
          <span :if={@checking_update} class="btn btn-sm btn-ghost loading loading-spinner loading-xs"></span>
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
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <div class="flex items-center justify-between">
            <h2 class="card-title text-lg">Configuration</h2>
            <button
              :if={@can?.(:configure) && !@editing_config && @config_schema != %{}}
              phx-click="edit_config"
              class="btn btn-ghost btn-sm"
            >
              Edit
            </button>
          </div>

          <%!-- Read-only view --%>
          <div :if={!@editing_config}>
            <div :if={@plugin.config == %{}} class="text-sm text-base-content/60">
              No configuration set. Click Edit to configure.
            </div>
            <div :if={@plugin.config != %{}} class="space-y-2">
              <div :for={{key, value} <- @plugin.config} class="flex gap-2">
                <span class="font-mono text-sm font-semibold">{key}:</span>
                <span :if={field_src(@config_schema, key) == "secret"} class="text-sm badge badge-ghost">
                  {secret_name(@secret_options, value)}
                </span>
                <span :if={field_src(@config_schema, key) == "agent"} class="text-sm badge badge-info">
                  {agent_name(@agent_options, value)}
                </span>
                <span :if={field_src(@config_schema, key) == nil} class="text-sm">{value}</span>
              </div>
            </div>
          </div>

          <%!-- Edit form --%>
          <form :if={@editing_config} phx-submit="save_config" class="space-y-4">
            <div :for={{key, schema} <- @config_schema} class="form-control">
              <label class="label">
                <span class="label-text font-mono">
                  {key}
                  <span :if={key in @required_keys} class="text-error">*</span>
                </span>
              </label>
              <%!-- Secret fields use a seal selector --%>
              <select
                :if={schema["src"] == "secret"}
                name={"config[#{key}]"}
                class="select select-bordered w-full"
              >
                <option value="">Select a seal...</option>
                <option
                  :for={{name, id} <- @secret_options}
                  value={id}
                  selected={Map.get(@config_form, key) == id}
                >
                  {name}
                </option>
              </select>
              <%!-- Agent fields use an agent selector --%>
              <select
                :if={schema["src"] == "agent"}
                name={"config[#{key}]"}
                class="select select-bordered w-full"
              >
                <option value="">Select a summon...</option>
                <option
                  :for={{name, id} <- @agent_options}
                  value={id}
                  selected={Map.get(@config_form, key) == id}
                >
                  {name}
                </option>
              </select>
              <%!-- Plain fields use text input --%>
              <input
                :if={is_nil(schema["src"])}
                type="text"
                name={"config[#{key}]"}
                value={Map.get(@config_form, key, "")}
                placeholder={schema["description"]}
                class="input input-bordered w-full"
              />
              <label :if={schema["description"]} class="label">
                <span class="label-text-alt text-base-content/50">{schema["description"]}</span>
              </label>
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Save</button>
              <button type="button" phx-click="cancel_config" class="btn btn-ghost btn-sm">
                Cancel
              </button>
            </div>
          </form>
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

  defp field_src(config_schema, key) do
    get_in(config_schema, [key, "src"])
  end

  defp secret_name(secret_options, secret_id) do
    case Enum.find(secret_options, fn {_name, id} -> id == secret_id end) do
      {name, _id} -> name
      nil -> "Unknown seal"
    end
  end

  defp agent_name(agent_options, agent_id) do
    case Enum.find(agent_options, fn {_name, id} -> id == agent_id end) do
      {name, _id} -> name
      nil -> "Unknown summon"
    end
  end
end
