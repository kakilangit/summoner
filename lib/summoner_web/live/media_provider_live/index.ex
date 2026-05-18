defmodule SummonerWeb.MediaProviderLive.Index do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.MediaProviders

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Forges - #{workspace.name}",
        media_providers:
          MediaProviders.list_media_providers(
            socket.assigns.current_scope,
            workspace.id,
            workspace.tenant_id
          )
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/realms/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Forges", nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    authorize(socket, :configure, fn -> do_delete(socket, id) end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Forges</h1>
        <.link
          :if={@can?.(:configure)}
          navigate={~p"/realms/#{@workspace.tenant_id}/realms/#{@workspace.id}/forges/new"}
          class="btn btn-primary btn-sm"
        >
          Add Forge
        </.link>
      </div>

      <div :if={@media_providers == []} class="text-center py-12 text-base-content/60">
        <p>No forges configured yet.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={mp <- @media_providers}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <span class="font-medium">{mp.name}</span>
              <span class="badge badge-sm badge-outline">{mp.provider.name}</span>
              <span :if={mp.tenant_id} class="badge badge-ghost badge-xs">Realm</span>
            </div>
            <div class="text-sm text-base-content/60">
              <span :if={mp.default_image_model}>
                Image Spirit: {mp.default_image_model}
              </span>
            </div>
          </div>
          <div class="flex gap-2 flex-shrink-0">
            <.link
              :if={@can?.(:configure) and is_nil(mp.tenant_id)}
              navigate={
                ~p"/realms/#{@workspace.tenant_id}/realms/#{@workspace.id}/forges/#{mp.id}/edit"
              }
              class="btn btn-ghost btn-sm"
            >
              Edit
            </.link>
            <button
              :if={@can?.(:configure) and is_nil(mp.tenant_id)}
              phx-click={show_confirm("#delete-media-provider-#{mp.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Delete
            </button>
            <.confirm_modal
              :if={@can?.(:configure) and is_nil(mp.tenant_id)}
              id={"delete-media-provider-#{mp.id}"}
              title="Delete forge?"
              message="This forge will be permanently removed."
              confirm_text="Delete"
              on_confirm={JS.push("delete", value: %{id: mp.id})}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp do_delete(socket, id) do
    scope = socket.assigns.current_scope
    workspace = socket.assigns.workspace
    provider = MediaProviders.get_media_provider!(scope, workspace.id, workspace.tenant_id, id)

    case MediaProviders.delete_media_provider(scope, provider) do
      {:ok, _} ->
        providers = MediaProviders.list_media_providers(scope, workspace.id, workspace.tenant_id)

        {:noreply,
         socket
         |> assign(media_providers: providers)
         |> put_flash(:info, "Forge deleted.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not delete media_provider.")}
    end
  end
end
