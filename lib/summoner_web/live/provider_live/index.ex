defmodule SummonerWeb.ProviderLive.Index do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Domain.Types.Presets
  alias Summoner.Ports.Persistence.Providers

  @sort_options [{"Name", :name}, {"Kind", :kind}, {"Status", :status}, {"Created", :inserted_at}]
  @default_sort_by :name
  @default_sort_dir :asc
  @filter_fields [:name, :kind, :base_url]

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Gateways - #{workspace.name}",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Gateways", nil}
        ]
      )
      |> load_page()

    {:ok, socket}
  end

  @impl true
  def handle_event("paginate", %{"page" => page_num}, socket) do
    {:noreply, socket |> assign(page_num: String.to_integer(page_num)) |> load_page()}
  end

  @impl true
  def handle_event("sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)

    sort_dir =
      if socket.assigns.sort_by == field,
        do: toggle_dir(socket.assigns.sort_dir),
        else: :asc

    {:noreply, socket |> assign(sort_by: field, sort_dir: sort_dir) |> load_page()}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, socket |> assign(filter: filter) |> load_page()}
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
        <h1 class="text-2xl font-bold">Gateways</h1>
        <.link
          :if={@can?.(:configure)}
          navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/gateways/new"}
          class="btn btn-primary btn-sm"
        >
          Add Gateway
        </.link>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search gateways..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>No gateways configured yet.</p>
        <p :if={@filter != ""}>No gateways match your search.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={provider <- @page.entries}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <.link
                navigate={
                  ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/gateways/#{provider.id}"
                }
                class="font-medium link link-hover"
              >
                {provider.name}
              </.link>
              <span class={[
                "badge badge-sm",
                provider.status == :online && "badge-success",
                provider.status == :offline && "badge-error",
                provider.status == :unknown && "badge-warning badge-outline"
              ]}>
                {provider.status}
              </span>
              <span :if={provider.tenant_id} class="badge badge-ghost badge-xs">Realm</span>
            </div>
            <div class="text-sm text-base-content/60">
              {provider_kind_label(provider.kind)} · {provider.type} · {provider.base_url}
            </div>
          </div>
          <div class="flex gap-2 flex-shrink-0">
            <.link
              :if={@can?.(:configure) and is_nil(provider.tenant_id)}
              navigate={
                ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/gateways/#{provider.id}/edit"
              }
              class="btn btn-ghost btn-sm"
            >
              Edit
            </.link>
            <button
              :if={@can?.(:configure) and is_nil(provider.tenant_id)}
              phx-click={show_confirm("#delete-provider-#{provider.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Delete
            </button>
            <.confirm_modal
              :if={@can?.(:configure) and is_nil(provider.tenant_id)}
              id={"delete-provider-#{provider.id}"}
              title="Delete gateway?"
              message="This gateway will be permanently removed. Summons bound to it will need a new gateway."
              confirm_text="Delete"
              on_confirm={JS.push("delete", value: %{id: provider.id})}
            />
          </div>
        </div>
      </div>

      <.pagination page={@page} />
    </div>
    """
  end

  defp load_page(socket) do
    %{current_scope: scope, workspace: workspace} = socket.assigns
    opts = list_opts(socket.assigns)
    page = Providers.list_providers_paginated(scope, workspace.id, workspace.tenant_id, opts)
    assign(socket, page: page)
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

  defp provider_kind_label(kind) do
    case Presets.provider(kind) do
      %{label: label} -> label
      _ -> kind
    end
  end

  defp do_delete(socket, id) do
    scope = socket.assigns.current_scope
    workspace = socket.assigns.workspace
    provider = Providers.get_provider!(scope, workspace.id, workspace.tenant_id, id)

    case Providers.delete_provider(scope, provider) do
      {:ok, _} ->
        {:noreply, socket |> load_page() |> put_flash(:info, "Gateway deleted.")}

      {:error, changeset} ->
        message =
          case changeset.errors[:agents] do
            {msg, _} -> msg
            _ -> "Could not delete gateway."
          end

        {:noreply, put_flash(socket, :error, message)}
    end
  end
end
