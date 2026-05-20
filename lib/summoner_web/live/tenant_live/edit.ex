defmodule SummonerWeb.TenantLive.Edit do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Tenants
  alias Summoner.Domain.Schemas.{Tenant, TenantSettings}

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.tenant_can?.(:manage_settings) do
      tenant = socket.assigns.tenant

      socket =
        socket
        |> assign(page_title: "Edit Guild - #{tenant.name}")
        |> assign(tenant_form: to_form(Tenant.changeset(tenant, %{}), as: "tenant"))
        |> assign(settings_form: to_form(TenantSettings.changeset(tenant.settings, %{})))
        |> assign(
          breadcrumbs: [
            {"Guilds", ~p"/guilds"},
            {tenant.name, ~p"/guilds/#{tenant.id}/realms"},
            {"Edit", nil}
          ]
        )

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to do that.")
       |> redirect(to: ~p"/guilds/#{socket.assigns.tenant.id}/realms")}
    end
  end

  @impl true
  def handle_event("save_tenant", %{"tenant" => params}, socket) do
    case Tenants.update_tenant(socket.assigns.tenant, params) do
      {:ok, tenant} ->
        {:noreply,
         socket
         |> assign(tenant: tenant)
         |> assign(page_title: "Edit Guild - #{tenant.name}")
         |> assign(tenant_form: to_form(Tenant.changeset(tenant, %{}), as: "tenant"))
         |> put_flash(:info, "Guild updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, tenant_form: to_form(changeset, as: "tenant"))}
    end
  end

  def handle_event("save_settings", %{"tenant_settings" => params}, socket) do
    case Tenants.update_settings(socket.assigns.tenant, params) do
      {:ok, settings} ->
        tenant = %{socket.assigns.tenant | settings: settings}

        {:noreply,
         socket
         |> assign(tenant: tenant)
         |> assign(settings_form: to_form(TenantSettings.changeset(settings, %{})))
         |> put_flash(:info, "Guild settings updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, settings_form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-8">
      <h1 class="text-2xl font-bold">Edit Guild</h1>

      <section class="space-y-3">
        <h2 class="text-lg font-semibold border-b border-base-300 pb-2">General</h2>
        <.form
          for={@tenant_form}
          id="tenant-form"
          phx-submit="save_tenant"
          class="space-y-4"
        >
          <.input field={@tenant_form[:name]} type="text" label="Name" required />
          <div>
            <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
              Save
            </.button>
          </div>
        </.form>
      </section>

      <section class="space-y-3">
        <h2 class="text-lg font-semibold border-b border-base-300 pb-2">Settings</h2>
        <.form
          for={@settings_form}
          id="settings-form"
          phx-submit="save_settings"
          class="space-y-4"
        >
          <.input
            field={@settings_form[:registration_mode]}
            type="select"
            label="Registration Mode"
            options={[
              {"Disabled", "disabled"},
              {"Invitation Only", "invitation"},
              {"Open", "open"}
            ]}
          />
          <.input
            field={@settings_form[:max_workspaces]}
            type="number"
            label="Max Realms"
            min="1"
            max="10000"
            required
          />
          <.input
            field={@settings_form[:max_members]}
            type="number"
            label="Max Members"
            min="1"
            max="100000"
            required
          />
          <.input
            field={@settings_form[:token_quota_monthly]}
            type="number"
            label="Monthly Token Quota"
            min="1"
            placeholder="Unlimited"
          />
          <.input
            field={@settings_form[:budget_usd_monthly]}
            type="number"
            label="Monthly Budget (USD)"
            min="0.01"
            step="0.01"
            placeholder="Unlimited"
          />
          <div>
            <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
              Save Settings
            </.button>
          </div>
        </.form>
      </section>
    </div>
    """
  end
end
