defmodule SummonerWeb.A2AServerLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.A2A, as: SummonerA2A
  alias Summoner.A2A.A2AServer
  alias Summoner.Agents
  alias Summoner.Workspaces.Policy

  @impl true
  def mount(params, _session, socket) do
    workspace = socket.assigns.workspace

    if Policy.can?(socket.assigns.membership, :configure) do
      scope = socket.assigns.current_scope

      {server, title} =
        case params["id"] do
          nil ->
            {%A2AServer{workspace_id: workspace.id}, "New Herald"}

          id ->
            {SummonerA2A.get_server!(scope, workspace.id, id), "Edit Herald"}
        end

      changeset = SummonerA2A.change_server(server)
      agents = Agents.list_agents(scope, workspace.id)

      # Filter to local agents only
      local_agents = Enum.filter(agents, &(&1.type == :local))

      socket =
        socket
        |> assign(page_title: "#{title} - #{workspace.name}")
        |> assign(
          server: server,
          form: to_form(changeset),
          title: title,
          editing: server.id != nil,
          local_agents: local_agents,
          endpoint_url: if(server.id, do: SummonerA2A.base_url(server), else: nil)
        )
        |> assign(
          breadcrumbs: [
            {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
            {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
            {"Heralds", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/heralds"},
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
  def handle_event("save", %{"a2a_server" => params}, socket) do
    if socket.assigns.editing do
      update_server(socket, params)
    else
      create_server(socket, params)
    end
  end

  defp create_server(socket, params) do
    workspace = socket.assigns.workspace
    params = Map.put(params, "workspace_id", workspace.id)

    case SummonerA2A.create_server(socket.assigns.current_scope, params) do
      {:ok, _server} ->
        {:noreply,
         socket
         |> put_flash(:info, "Herald created.")
         |> push_navigate(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/heralds")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_server(socket, params) do
    workspace = socket.assigns.workspace

    case SummonerA2A.update_server(
           socket.assigns.current_scope,
           socket.assigns.server,
           params
         ) do
      {:ok, _server} ->
        {:noreply,
         socket
         |> put_flash(:info, "Herald updated.")
         |> push_navigate(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/heralds")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <h1 class="text-2xl font-bold">{@title}</h1>

      <div :if={@endpoint_url} class="alert alert-info text-sm">
        <span>Endpoint: <code class="font-mono">{@endpoint_url}</code></span>
      </div>

      <.form for={@form} id="herald-form" phx-submit="save" class="space-y-4">
        <.input
          field={@form[:agent_id]}
          type="select"
          label="Summon"
          options={Enum.map(@local_agents, &{&1.name, &1.id})}
          prompt="Select a summon..."
          required
          disabled={@editing}
        />

        <.input
          field={@form[:auth_mode]}
          type="select"
          label="Authentication"
          options={[
            {"None", "none"},
            {"Bearer Token", "bearer_token"},
            {"API Key", "api_key"}
          ]}
        />

        <.input
          field={@form[:api_key]}
          type="password"
          label="API Key / Token"
          placeholder={if @editing, do: "Leave blank to keep current", else: ""}
        />

        <.input
          field={@form[:rate_limit_rpm]}
          type="number"
          label="Rate limit (requests/minute)"
        />

        <.input field={@form[:enabled]} type="checkbox" label="Enabled" />

        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/heralds"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Herald", else: "Create Herald"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end
end
