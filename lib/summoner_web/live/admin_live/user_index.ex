defmodule SummonerWeb.AdminLive.UserIndex do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Admin

  @sort_options [{"Email", :email}, {"Role", :role}, {"Registered", :inserted_at}]
  @default_sort_by :email
  @default_sort_dir :asc
  @filter_fields [:email]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Admin — Users",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options,
        show_create_form: false,
        create_form: to_form(%{"email" => "", "password" => "", "role" => "user"}, as: "user")
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

  def handle_event("toggle_create_form", _params, socket) do
    {:noreply, assign(socket, show_create_form: !socket.assigns.show_create_form)}
  end

  def handle_event("create_user", %{"user" => user_params}, socket) do
    case Admin.create_user(user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User created successfully.")
         |> assign(
           show_create_form: false,
           create_form: to_form(%{"email" => "", "password" => "", "role" => "user"}, as: "user")
         )
         |> load_page()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, create_form: to_form(changeset, as: "user"))}

      {:error, reason} when is_atom(reason) ->
        {:noreply, put_flash(socket, :error, "Failed to create user: #{reason}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Users</h1>
        <div class="flex gap-2">
          <button phx-click="toggle_create_form" class="btn btn-primary btn-sm">
            Create User
          </button>
          <.link navigate="/admin" class="btn btn-ghost btn-sm">Back to Dashboard</.link>
        </div>
      </div>

      <div :if={@show_create_form} class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title text-lg">Create User</h2>
          <.form for={@create_form} phx-submit="create_user" class="space-y-4">
            <.input field={@create_form[:email]} type="email" label="Email" required />
            <.input
              field={@create_form[:password]}
              type="password"
              label="Password"
              required
              minlength="12"
            />
            <label class="label cursor-pointer justify-start gap-2">
              <input
                type="checkbox"
                name="user[role]"
                value="admin"
                class="checkbox checkbox-sm"
                checked={
                  Phoenix.HTML.Form.normalize_value(
                    "checkbox",
                    @create_form[:role].value == "admin"
                  )
                }
              />
              <span class="label-text">Admin role</span>
            </label>
            <input
              :if={@create_form[:role].value != "admin"}
              type="hidden"
              name="user[role]"
              value="user"
            />
            <div class="flex gap-2">
              <.button class="btn btn-primary btn-sm">Create</.button>
              <button type="button" phx-click="toggle_create_form" class="btn btn-ghost btn-sm">
                Cancel
              </button>
            </div>
          </.form>
        </div>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search by email..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>No users yet.</p>
        <p :if={@filter != ""}>No users match your search.</p>
      </div>

      <div :if={@page.entries != []} class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Email</th>
              <th>Role</th>
              <th>Status</th>
              <th>Registered</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={user <- @page.entries} class="hover">
              <td>
                {user.email}
                <span :if={Admin.root_admin?(user)} class="badge badge-warning badge-xs ml-1">
                  Root
                </span>
              </td>
              <td>
                <span class={[
                  "badge badge-sm",
                  user.role == "admin" && "badge-primary",
                  user.role == "user" && "badge-ghost"
                ]}>
                  {user.role}
                </span>
              </td>
              <td>
                <span :if={user.disabled_at} class="badge badge-sm badge-error">Disabled</span>
                <span
                  :if={is_nil(user.disabled_at) && user.confirmed_at}
                  class="badge badge-sm badge-success"
                >
                  Active
                </span>
                <span
                  :if={is_nil(user.disabled_at) && is_nil(user.confirmed_at)}
                  class="badge badge-sm badge-warning"
                >
                  Unconfirmed
                </span>
              </td>
              <td class="text-xs text-base-content/60">
                {Summoner.Services.TimeZone.format(user.inserted_at,
                  format: "%Y-%m-%d",
                  show_zone: false
                )}
              </td>
              <td>
                <.link navigate={"/admin/users/#{user.id}"} class="btn btn-ghost btn-xs">
                  View
                </.link>
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
    assign(socket, page: Admin.list_users(list_opts(socket.assigns)))
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
