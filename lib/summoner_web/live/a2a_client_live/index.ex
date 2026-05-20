defmodule SummonerWeb.A2AClientLive.Index do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Adapters.Persistence.Agents

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Envoys - #{workspace.name}",
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Envoys", nil}
        ]
      )
      |> load_envoys()

    {:ok, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    authorize(socket, :configure, fn ->
      scope = socket.assigns.current_scope
      workspace = socket.assigns.workspace
      agent = Agents.get_agent!(scope, workspace.id, id)

      case Agents.delete_agent(scope, agent) do
        {:ok, _} ->
          {:noreply, socket |> load_envoys() |> put_flash(:info, "Envoy removed.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not remove envoy.")}
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Envoys</h1>
        <.link
          :if={@can?.(:configure)}
          navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/envoys/new"}
          class="btn btn-primary btn-sm"
        >
          New Envoy
        </.link>
      </div>

      <div :if={@envoys == []} class="text-center py-12 text-base-content/60">
        <p>No envoys configured. Connect a remote A2A agent.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={agent <- @envoys}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <span class="font-medium">{agent.name}</span>
              <span class={"badge badge-xs #{status_badge(agent.remote_agent)}"}>
                {agent.remote_agent.status}
              </span>
              <span class="badge badge-ghost badge-xs">{agent.remote_agent.auth_mode}</span>
            </div>
            <div class="text-sm text-base-content/60 truncate">
              {agent.remote_agent.agent_card_url}
            </div>
          </div>
          <div class="flex gap-2 flex-shrink-0">
            <.link
              :if={@can?.(:configure)}
              navigate={
                ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/envoys/#{agent.id}/edit"
              }
              class="btn btn-ghost btn-sm"
            >
              Edit
            </.link>
            <button
              :if={@can?.(:configure)}
              phx-click={show_confirm("#delete-envoy-#{agent.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Delete
            </button>
            <.confirm_modal
              :if={@can?.(:configure)}
              id={"delete-envoy-#{agent.id}"}
              title="Delete envoy?"
              message="This will disconnect the remote agent. Active tasks will be interrupted."
              confirm_text="Delete"
              on_confirm={JS.push("delete", value: %{id: agent.id})}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp load_envoys(socket) do
    scope = socket.assigns.current_scope
    workspace = socket.assigns.workspace
    envoys = Agents.list_remote_agents(scope, workspace.id)
    assign(socket, envoys: envoys)
  end

  defp status_badge(%{status: :online}), do: "badge-success"
  defp status_badge(%{status: :offline}), do: "badge-error"
  defp status_badge(_), do: "badge-ghost"
end
