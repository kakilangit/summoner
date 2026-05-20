defmodule SummonerWeb.AgentLive.Tools do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.MCP

  @impl true
  def mount(%{"id" => agent_id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope

    agent = Agents.get_agent!(scope, workspace.id, agent_id)
    all_servers = MCP.list_servers(scope, workspace.id, workspace.tenant_id)
    equipped_map = build_equipped_map(agent.id)

    socket =
      socket
      |> assign(page_title: "Runes - #{agent.name}")
      |> assign(
        agent: agent,
        all_servers: all_servers,
        equipped_map: equipped_map,
        editing_env: nil,
        env_text: "",
        env_hint: ""
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Summons", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/summons"},
          {agent.name,
           ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/summons/#{agent.id}"},
          {"Runes", nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("equip", %{"server-id" => server_id}, socket) do
    scope = socket.assigns.current_scope
    agent = socket.assigns.agent

    case MCP.equip_server(scope, %{agent_id: agent.id, mcp_server_id: server_id}) do
      {:ok, _} ->
        {:noreply, assign(socket, equipped_map: build_equipped_map(agent.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not equip rune.")}
    end
  end

  @impl true
  def handle_event("unequip", %{"server-id" => server_id}, socket) do
    scope = socket.assigns.current_scope
    agent = socket.assigns.agent

    case MCP.unequip_server(scope, agent.id, server_id) do
      {:ok, _} ->
        {:noreply, assign(socket, equipped_map: build_equipped_map(agent.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not unequip rune.")}
    end
  end

  @impl true
  def handle_event("toggle", %{"server-id" => server_id}, socket) do
    scope = socket.assigns.current_scope
    agent = socket.assigns.agent

    case MCP.toggle_server(scope, agent.workspace_id, agent.id, server_id) do
      {:ok, _} ->
        {:noreply, assign(socket, equipped_map: build_equipped_map(agent.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not toggle rune.")}
    end
  end

  @impl true
  def handle_event("edit_env", %{"server-id" => server_id}, socket) do
    agent = socket.assigns.agent

    case MCP.get_equipped_env(agent.id, server_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Rune not equipped.")}

      record ->
        server = Enum.find(socket.assigns.all_servers, &(&1.id == server_id))
        env_text = format_env(record.env)
        hint = env_placeholder(server)
        {:noreply, assign(socket, editing_env: server_id, env_text: env_text, env_hint: hint)}
    end
  end

  @impl true
  def handle_event("cancel_env", _params, socket) do
    {:noreply, assign(socket, editing_env: nil, env_text: "", env_hint: "")}
  end

  @impl true
  def handle_event("save_env", %{"env_text" => env_text}, socket) do
    scope = socket.assigns.current_scope
    agent = socket.assigns.agent
    server_id = socket.assigns.editing_env

    env = parse_env(env_text)

    case MCP.update_equipped_env(scope, agent.id, server_id, env) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(editing_env: nil, env_text: "", env_hint: "")
         |> put_flash(:info, "Environment saved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save environment.")}
    end
  end

  # Returns %{server_id => enabled?} for equipped servers
  defp build_equipped_map(agent_id) do
    agent_id
    |> MCP.list_all_equipped_servers()
    |> Map.new(fn {server, enabled} -> {server.id, enabled} end)
  end

  defp parse_env(text) do
    text
    |> String.split("\n")
    |> Enum.reject(fn line ->
      trimmed = String.trim(line)
      trimmed == "" or String.starts_with?(trimmed, "#")
    end)
    |> Enum.map(fn line ->
      case String.split(line, "=", parts: 2) do
        [key, value] -> {String.trim(key), String.trim(value)}
        [key] -> {String.trim(key), ""}
      end
    end)
    |> Map.new()
  end

  defp format_env(nil), do: ""
  defp format_env(env) when env == %{}, do: ""

  defp format_env(env) do
    env
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map_join("\n", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp env_placeholder(nil), do: ""

  defp env_placeholder(server) do
    case Map.get(server.config, "env", %{}) do
      env when env == %{} or is_nil(env) ->
        ""

      env ->
        Enum.sort_by(env, fn {k, _} -> k end) |> Enum.map_join("\n", fn {k, _} -> "#{k}=" end)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">Runes for {@agent.name}</h1>

      <p class="text-sm text-base-content/60">
        Equip runes and optionally set per-summon environment overrides.
        Use <code>$WARD_NAME</code> syntax to reference seals, or set values directly.
      </p>

      <div :if={@all_servers == []} class="text-center py-12 text-base-content/60">
        <p>
          No runes available.
          <.link
            navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/runes/new"}
            class="link"
          >
            Add one first.
          </.link>
        </p>
      </div>

      <div class="space-y-2">
        <div
          :for={server <- @all_servers}
          class="p-4 bg-base-200 rounded-lg"
        >
          <div class="flex items-center justify-between">
            <div>
              <div class="flex items-center gap-2">
                <span class="font-medium">{server.name}</span>
                <span class="badge badge-sm">{server.transport}</span>
              </div>
              <div class="text-sm text-base-content/60 font-mono truncate max-w-md">
                {server.command_or_url}
              </div>
            </div>
            <div class="flex items-center gap-2">
              <%= if Map.has_key?(@equipped_map, server.id) do %>
                <label class="swap" title={if @equipped_map[server.id], do: "On", else: "Off"}>
                  <input
                    type="checkbox"
                    checked={@equipped_map[server.id]}
                    phx-click="toggle"
                    phx-value-server-id={server.id}
                  />
                  <span class="swap-on text-success text-sm font-medium">ON</span>
                  <span class="swap-off text-base-content/40 text-sm font-medium">OFF</span>
                </label>
                <button
                  phx-click="edit_env"
                  phx-value-server-id={server.id}
                  class="btn btn-sm btn-ghost"
                  title="Configure environment"
                >
                  Config
                </button>
                <button
                  phx-click="unequip"
                  phx-value-server-id={server.id}
                  class="btn btn-sm btn-error btn-outline"
                >
                  Unequip
                </button>
              <% else %>
                <button
                  phx-click="equip"
                  phx-value-server-id={server.id}
                  class="btn btn-sm btn-primary btn-outline"
                >
                  Equip
                </button>
              <% end %>
            </div>
          </div>

          <%= if @editing_env == server.id do %>
            <div class="mt-4 border-t border-base-300 pt-4">
              <form phx-submit="save_env" class="space-y-3">
                <p class="text-xs text-base-content/50">
                  One per line: <code>KEY=VALUE</code>. Use <code>$WARD_NAME</code>
                  to reference seals. These override the rune's default env.
                </p>
                <.text_editor
                  id={"env-override-#{server.id}"}
                  name="env_text"
                  value={@env_text}
                  label="Environment overrides"
                  placeholder={@env_hint}
                  rows={6}
                />
                <div class="flex gap-2">
                  <button type="submit" class="btn btn-sm btn-primary">Save</button>
                  <button type="button" phx-click="cancel_env" class="btn btn-sm btn-ghost">
                    Cancel
                  </button>
                </div>
              </form>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
