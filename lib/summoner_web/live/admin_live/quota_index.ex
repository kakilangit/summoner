defmodule SummonerWeb.AdminLive.QuotaIndex do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Invitations

  @sort_options [{"Amount", :amount}, {"Created", :inserted_at}]
  @default_sort_by :amount
  @default_sort_dir :desc
  @filter_fields []

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Admin — Summon Quotas",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">All Summon Quotas</h1>
        <.link navigate="/admin" class="btn btn-ghost btn-sm">Back to Dashboard</.link>
      </div>

      <div class="text-sm text-base-content/60">
        Summon quotas are managed per-realm. Guild admins have unlimited quota within their realm.
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search quotas..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p>No quotas configured yet.</p>
      </div>

      <div :if={@page.entries != []} class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>User</th>
              <th>Guild</th>
              <th>Remaining</th>
              <th>Role</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={quota <- @page.entries} class="hover">
              <td>{quota.user.email}</td>
              <td class="text-sm">
                {if quota.tenant, do: quota.tenant.name, else: "—"}
              </td>
              <td>{quota.amount}</td>
              <td>
                <span class={[
                  "badge badge-sm",
                  quota.user.role == "admin" && "badge-primary",
                  quota.user.role == "user" && "badge-ghost"
                ]}>
                  {quota.user.role}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.pagination page={@page} />
    </div>
    """
  end

  defp load_page(socket) do
    assign(socket, page: Invitations.list_all_quotas(list_opts(socket.assigns)))
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
