defmodule SummonerWeb.WorkspaceLive.New do
  use SummonerWeb, :live_view

  alias Summoner.Adapters.Persistence.Workspaces
  alias Summoner.Domain.Schemas.Workspace

  @impl true
  def mount(_params, _session, socket) do
    changeset = Workspace.changeset(%Workspace{}, %{})

    socket =
      socket
      |> assign(page_title: "New Realm")
      |> assign(form: to_form(changeset))
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{socket.assigns.tenant.id}/realms"},
          {"New Realm", nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("save", %{"workspace" => params}, socket) do
    tenant = socket.assigns.tenant

    case Workspaces.create_workspace(socket.assigns.current_scope, tenant.id, params) do
      {:ok, workspace} ->
        socket =
          socket
          |> put_flash(:info, "Realm created successfully.")
          |> push_navigate(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <h1 class="text-2xl font-bold">New Realm</h1>

      <.form for={@form} id="workspace-form" phx-submit="save" class="space-y-4">
        <.input field={@form[:name]} type="text" label="Name" required />
        <div class="flex items-center gap-4">
          <.link navigate={~p"/guilds/#{@tenant.id}/realms"} class="btn btn-ghost btn-sm">
            Cancel
          </.link>
          <.button phx-disable-with="Creating..." class="btn btn-primary btn-sm">
            Create Realm
          </.button>
        </div>
      </.form>
    </div>
    """
  end
end
