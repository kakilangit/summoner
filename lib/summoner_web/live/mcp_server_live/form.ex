defmodule SummonerWeb.McpServerLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.MCP
  alias Summoner.MCP.McpServer
  alias Summoner.Presets
  alias Summoner.Workspaces.Policy

  @impl true
  def mount(params, _session, socket) do
    workspace = socket.assigns.workspace

    if Policy.can?(socket.assigns.membership, :configure) do
      scope = socket.assigns.current_scope

      {server, title} =
        case params["id"] do
          nil ->
            {%McpServer{workspace_id: workspace.id}, "New Rune"}

          id ->
            {MCP.get_server!(scope, workspace.id, workspace.tenant_id, id), "Edit Rune"}
        end

      changeset = McpServer.changeset(server, %{})
      env_text = format_env(server.config)

      socket =
        socket
        |> assign(page_title: "#{title} - #{workspace.name}")
        |> assign(
          server: server,
          form: to_form(changeset),
          title: title,
          editing: server.id != nil,
          preset_options: Presets.mcp_server_options(),
          selected_preset: "",
          env_text: env_text
        )
        |> assign(
          breadcrumbs: [
            {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
            {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
            {"Runes", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/runes"},
            {title, nil}
          ]
        )

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to do that.")
       |> redirect(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}")}
    end
  end

  @impl true
  def handle_event("validate", %{"mcp_server" => params} = raw, socket) do
    {params, env_text} =
      maybe_apply_preset(params, raw["preset"], socket.assigns.selected_preset)

    selected = raw["preset"] || socket.assigns.selected_preset
    env_text = env_text || raw["env_text"] || socket.assigns.env_text

    changeset =
      socket.assigns.server
      |> McpServer.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply,
     assign(socket, form: to_form(changeset), selected_preset: selected, env_text: env_text)}
  end

  @impl true
  def handle_event("save", %{"mcp_server" => params} = raw, socket) do
    env_text = raw["env_text"] || ""
    config = build_config(env_text)
    params = Map.put(params, "config", config)

    if socket.assigns.editing do
      update_server(socket, params)
    else
      create_server(socket, params)
    end
  end

  defp maybe_apply_preset(params, key, last)
       when is_binary(key) and key != "" and key != last do
    case Presets.mcp_server(key) do
      nil ->
        {params, nil}

      preset ->
        params =
          Map.merge(params, %{
            "name" => preset.name,
            "transport" => preset.transport,
            "command_or_url" => preset.command_or_url
          })

        env_hint = Map.get(preset, :env_hint, "") |> normalize_env_hint()
        {params, env_hint}
    end
  end

  defp maybe_apply_preset(params, _key, _last), do: {params, nil}

  defp build_config(env_text) do
    env = parse_env(env_text)

    if env == %{} do
      %{}
    else
      %{"env" => env}
    end
  end

  defp parse_env(text) when is_binary(text) do
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

  defp parse_env(_), do: %{}

  # Convert space-separated "KEY=VAL KEY2=VAL2" hints into newline-separated
  defp normalize_env_hint(""), do: ""

  defp normalize_env_hint(hint) do
    hint
    |> String.split(~r/\s+(?=\w+=)/)
    |> Enum.join("\n")
  end

  defp format_env(nil), do: ""
  defp format_env(config) when config == %{}, do: ""

  defp format_env(config) do
    case Map.get(config, "env", %{}) do
      env when env == %{} or is_nil(env) ->
        ""

      env ->
        env
        |> Enum.sort_by(fn {k, _} -> k end)
        |> Enum.map_join("\n", fn {k, v} -> "#{k}=#{v}" end)
    end
  end

  defp create_server(socket, params) do
    workspace = socket.assigns.workspace
    params = Map.put(params, "workspace_id", workspace.id)

    case MCP.create_server(socket.assigns.current_scope, params) do
      {:ok, _server} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rune created.")
         |> push_navigate(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/runes")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_server(socket, params) do
    workspace = socket.assigns.workspace

    case MCP.update_server(socket.assigns.current_scope, socket.assigns.server, params) do
      {:ok, _server} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rune updated.")
         |> push_navigate(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/runes")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <h1 class="text-2xl font-bold">{@title}</h1>

      <.form
        for={@form}
        id="mcp-server-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <div :if={!@editing} class="form-control">
          <label class="label">
            <span class="label-text font-medium">Preset</span>
          </label>
          <select name="preset" class="select select-bordered select-sm w-full">
            {Phoenix.HTML.Form.options_for_select(@preset_options, @selected_preset)}
          </select>
        </div>

        <.input field={@form[:name]} type="text" label="Name" required phx-debounce="300" />
        <.input
          field={@form[:transport]}
          type="select"
          label="Transport"
          options={[{"Stdio", :stdio}, {"HTTP", :http}]}
          required
        />
        <.input
          field={@form[:command_or_url]}
          type="text"
          label="Command / URL"
          placeholder="npx -y @modelcontextprotocol/server-everything or https://..."
          required
        />

        <div class="form-control">
          <p class="text-xs text-base-content/50 mb-1">
            One per line: <code>KEY=VALUE</code>. Use <code>$WARD_NAME</code>
            to reference seals. Can be overridden per-summon.
          </p>
          <.text_editor
            id="mcp-env-text"
            name="env_text"
            value={@env_text}
            label="Environment"
            placeholder="API_KEY=$MY_API_KEY\nSERVER_URL=http://localhost:8080"
            rows={6}
          />
        </div>

        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/runes"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Rune", else: "Add Rune"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end
end
