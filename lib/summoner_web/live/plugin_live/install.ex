defmodule SummonerWeb.PluginLive.Install do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Services.Plugins

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Install Grimoire - #{workspace.name}",
        image_ref: "",
        installing: false
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Grimoires", ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/plugins"},
          {"Install", nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"image_ref" => image_ref}, socket) do
    {:noreply, assign(socket, image_ref: image_ref)}
  end

  @impl true
  def handle_event("install", %{"image_ref" => image_ref}, socket) do
    authorize(socket, :configure, fn ->
      socket = assign(socket, installing: true)
      workspace = socket.assigns.workspace

      case Plugins.install(workspace.id, image_ref) do
        {:ok, plugin} ->
          {:noreply,
           socket
           |> put_flash(:info, "Grimoire #{plugin.name} installed.")
           |> push_navigate(
             to:
               ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/plugins/#{plugin.id}"
           )}

        {:error, %Ecto.Changeset{} = changeset} ->
          message = format_changeset_errors(changeset)

          {:noreply,
           socket |> assign(installing: false) |> put_flash(:error, "Install failed: #{message}")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(installing: false)
           |> put_flash(:error, "Install failed: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">Install Grimoire</h1>

      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <form phx-submit="install" phx-change="validate" class="space-y-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text">OCI Image Reference</span>
              </label>
              <input
                type="text"
                name="image_ref"
                value={@image_ref}
                placeholder="ghcr.io/summoner/grimoire-slack:1.0.0"
                class="input input-bordered w-full"
                required
              />
              <label class="label">
                <span class="label-text-alt text-base-content/60">
                  Docker/OCI image containing a grimoire.json manifest
                </span>
              </label>
            </div>

            <div class="flex gap-2">
              <button
                type="submit"
                class={["btn btn-primary", @installing && "loading"]}
                disabled={@image_ref == "" || @installing}
              >
                {if @installing, do: "Installing...", else: "Install"}
              </button>
              <.link
                navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/plugins"}
                class="btn btn-ghost"
              >
                Cancel
              </.link>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end
end
