defmodule SummonerWeb.TenantMediaProviderLive.Index do
  use SummonerWeb, :live_view

  alias Summoner.MediaProviders

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns.tenant

    socket =
      socket
      |> assign(
        page_title: "Forges - #{tenant.name}",
        media_providers: MediaProviders.list_tenant_media_providers(tenant.id)
      )
      |> assign(
        breadcrumbs: [
          {"Guilds", ~p"/guilds"},
          {tenant.name, ~p"/realms/#{tenant.id}/realms"},
          {"Forges", nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    if socket.assigns.tenant_can?.(:manage_resources) do
      do_delete(socket, id)
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    end
  end

  defp do_delete(socket, id) do
    tenant = socket.assigns.tenant
    provider = MediaProviders.get_tenant_media_provider!(tenant.id, id)

    case MediaProviders.delete_media_provider(socket.assigns.current_scope, provider) do
      {:ok, _} ->
        providers = MediaProviders.list_tenant_media_providers(tenant.id)

        {:noreply,
         socket
         |> assign(media_providers: providers)
         |> put_flash(:info, "Forge deleted.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not delete forge.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Forges</h1>
        <.link
          :if={@tenant_can?.(:manage_resources)}
          navigate={~p"/realms/#{@tenant.id}/forges/new"}
          class="btn btn-primary btn-sm"
        >
          Add Forge
        </.link>
      </div>

      <div :if={@media_providers == []} class="text-center py-12 text-base-content/60">
        <p>No realm forges configured yet.</p>
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
            </div>
            <div class="text-sm text-base-content/60">
              <span :if={mp.default_image_model}>
                Image Spirit: {mp.default_image_model}
              </span>
            </div>
          </div>
          <div class="flex gap-2 flex-shrink-0">
            <.link
              :if={@tenant_can?.(:manage_resources)}
              navigate={~p"/realms/#{@tenant.id}/forges/#{mp.id}/edit"}
              class="btn btn-ghost btn-sm"
            >
              Edit
            </.link>
            <button
              :if={@tenant_can?.(:manage_resources)}
              phx-click={show_confirm("#delete-media-provider-#{mp.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Delete
            </button>
            <.confirm_modal
              :if={@tenant_can?.(:manage_resources)}
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
end
