defmodule SummonerWeb.TenantLive.New do
  use SummonerWeb, :live_view

  alias Summoner.Domain.Schemas.Scope
  alias Summoner.Domain.Schemas.Tenant
  alias Summoner.Ports.Persistence.Tenants

  @impl true
  def mount(_params, _session, socket) do
    if Scope.admin?(socket.assigns.current_scope) do
      socket =
        socket
        |> assign(page_title: "New Guild")
        |> assign(form: to_form(Tenant.changeset(%Tenant{}, %{}), as: "tenant"))

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to do that.")
       |> redirect(to: ~p"/guilds")}
    end
  end

  @impl true
  def handle_event("save", %{"tenant" => params}, socket) do
    case Tenants.create_tenant(socket.assigns.current_scope, params) do
      {:ok, tenant} ->
        {:noreply,
         socket
         |> put_flash(:info, "Guild created.")
         |> push_navigate(to: ~p"/guilds/#{tenant.id}/realms")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "tenant"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-8">
      <h1 class="text-2xl font-bold">New Guild</h1>

      <.form for={@form} id="tenant-form" phx-submit="save" class="space-y-4">
        <.input field={@form[:name]} type="text" label="Name" required />
        <div class="flex gap-2">
          <.button phx-disable-with="Creating..." class="btn btn-primary btn-sm">
            Create Guild
          </.button>
          <.link navigate={~p"/guilds"} class="btn btn-ghost btn-sm">
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end
end
