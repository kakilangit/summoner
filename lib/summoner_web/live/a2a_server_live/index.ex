defmodule SummonerWeb.A2AServerLive.Index do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.A2A, as: SummonerA2A

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Heralds - #{workspace.name}",
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Heralds", nil}
        ]
      )
      |> load_servers()

    {:ok, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    authorize(socket, :configure, fn ->
      scope = socket.assigns.current_scope
      workspace = socket.assigns.workspace
      server = SummonerA2A.get_server!(scope, workspace.id, id)

      case SummonerA2A.delete_server(scope, server) do
        {:ok, _} ->
          {:noreply, socket |> load_servers() |> put_flash(:info, "Herald removed.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not remove herald.")}
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Heralds</h1>
        <.link
          :if={@can?.(:configure)}
          navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/heralds/new"}
          class="btn btn-primary btn-sm"
        >
          New Herald
        </.link>
      </div>

      <div :if={@servers == []} class="text-center py-12 text-base-content/60">
        <p>No heralds configured. Expose a summon via the A2A protocol.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={server <- @servers}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <span class="font-medium">{server.agent.name}</span>
              <span class={"badge badge-xs #{if server.enabled, do: "badge-success", else: "badge-ghost"}"}>
                {if server.enabled, do: "Active", else: "Disabled"}
              </span>
              <span class="badge badge-ghost badge-xs">{server.auth_mode}</span>
            </div>
            <div class="text-sm text-base-content/60">
              {server.auth_mode} | {server.rate_limit_rpm} rpm
            </div>
          </div>
          <div class="flex gap-2 flex-shrink-0">
            <.link
              :if={@can?.(:configure)}
              navigate={
                ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/heralds/#{server.id}/edit"
              }
              class="btn btn-ghost btn-sm"
            >
              Edit
            </.link>
            <button
              :if={@can?.(:configure)}
              phx-click={show_confirm("#delete-herald-#{server.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Delete
            </button>
            <.confirm_modal
              :if={@can?.(:configure)}
              id={"delete-herald-#{server.id}"}
              title="Delete herald?"
              message="This will stop exposing the agent via A2A. Active tasks will be interrupted."
              confirm_text="Delete"
              on_confirm={JS.push("delete", value: %{id: server.id})}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp load_servers(socket) do
    scope = socket.assigns.current_scope
    workspace = socket.assigns.workspace
    servers = SummonerA2A.list_servers(scope, workspace.id)
    assign(socket, servers: servers)
  end
end
