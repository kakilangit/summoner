defmodule SummonerWeb.TenantInvitationLive.Index do
  use SummonerWeb, :live_view

  alias Summoner.Domain.Schemas.Invitation
  alias Summoner.Ports.Persistence.Invitations

  @sort_options [{"Created", :inserted_at}, {"Expires", :expires_at}, {"Code", :code}]
  @default_sort_by :inserted_at
  @default_sort_dir :desc
  @filter_fields [:code]

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns.tenant
    user = socket.assigns.current_scope.user
    remaining = Invitations.remaining_quota(user, tenant.id)

    socket =
      socket
      |> assign(
        page_title: "Invites - #{tenant.name}",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options,
        remaining_quota: remaining
      )
      |> assign(
        breadcrumbs: [
          {"Guilds", ~p"/guilds"},
          {tenant.name, ~p"/guilds/#{tenant.id}/realms"},
          {"Invites", nil}
        ]
      )
      |> load_page()

    {:ok, socket}
  end

  @impl true
  def handle_event("paginate", %{"page" => page_num}, socket) do
    {:noreply, socket |> assign(page_num: String.to_integer(page_num)) |> load_page()}
  end

  def handle_event("sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)

    sort_dir =
      if socket.assigns.sort_by == field,
        do: toggle_dir(socket.assigns.sort_dir),
        else: :asc

    {:noreply, socket |> assign(sort_by: field, sort_dir: sort_dir) |> load_page()}
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, socket |> assign(filter: filter) |> load_page()}
  end

  def handle_event("create_invitation", _params, socket) do
    user = socket.assigns.current_scope.user
    tenant = socket.assigns.tenant

    case Invitations.create_tenant_invitation(user, tenant.id) do
      {:ok, invitation} ->
        remaining = Invitations.remaining_quota(user, tenant.id)

        {:noreply,
         socket
         |> put_flash(:info, "Invite created: #{invitation.code}")
         |> assign(remaining_quota: remaining)
         |> load_page()}

      {:error, :no_quota} ->
        {:noreply, put_flash(socket, :error, "No summon quota remaining.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create summon.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Invites</h1>
        <div class="flex items-center gap-4">
          <span class="text-sm text-base-content/60">
            Remaining:
            <span class="font-semibold">
              {if @remaining_quota == :unlimited, do: "Unlimited", else: @remaining_quota}
            </span>
          </span>
          <button phx-click="create_invitation" class="btn btn-primary btn-sm">
            Create Invite
          </button>
        </div>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search by code..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>No summons yet.</p>
        <p :if={@filter != ""}>No summons match your search.</p>
      </div>

      <div :if={@page.entries != []} class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Code</th>
              <th>Status</th>
              <th>Created By</th>
              <th>Used By</th>
              <th>Expires</th>
              <th>Created</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={inv <- @page.entries} class="hover">
              <td>
                <code class="text-xs">{inv.code}</code>
              </td>
              <td>
                <.invitation_badge invitation={inv} />
              </td>
              <td class="text-sm">{inv.invited_by.email}</td>
              <td class="text-sm">{if inv.used_by, do: inv.used_by.email, else: "—"}</td>
              <td class="text-xs text-base-content/60">
                {Summoner.Services.TimeZone.format(inv.expires_at,
                  format: "%Y-%m-%d",
                  show_zone: false
                )}
              </td>
              <td class="text-xs text-base-content/60">
                {Summoner.Services.TimeZone.format(inv.inserted_at,
                  format: "%Y-%m-%d",
                  show_zone: false
                )}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.pagination page={@page} />
    </div>
    """
  end

  defp invitation_badge(assigns) do
    status = Invitation.status(assigns.invitation)
    assigns = assign(assigns, :status, status)

    ~H"""
    <span :if={@status == :available} class="badge badge-sm badge-success">Available</span>
    <span :if={@status == :used} class="badge badge-sm badge-info">Used</span>
    <span :if={@status == :expired} class="badge badge-sm badge-error">Expired</span>
    """
  end

  defp load_page(socket) do
    tenant = socket.assigns.tenant
    opts = list_opts(socket.assigns)
    assign(socket, page: Invitations.list_tenant_invitations(tenant.id, opts))
  end

  defp list_opts(assigns) do
    [
      page: Map.get(assigns, :page_num, assigns[:page] && assigns.page.page) || 1,
      sort_by: assigns.sort_by,
      sort_dir: assigns.sort_dir,
      filter: assigns.filter,
      filter_fields: @filter_fields
    ]
  end

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc
end
