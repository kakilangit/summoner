defmodule SummonerWeb.EventRuleLive.Index do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Services.EventRules

  @sort_options [{"Name", :name}, {"Event", :event_type}, {"Priority", :priority}]
  @default_sort_by :priority
  @default_sort_dir :asc
  @filter_fields [:name]

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Omens - #{workspace.name}",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Omens", nil}
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
  def handle_event("toggle", %{"id" => id, "enabled" => enabled}, socket) do
    authorize(socket, :configure, fn ->
      scope = socket.assigns.current_scope
      workspace = socket.assigns.workspace
      rule = EventRules.get_rule!(scope, workspace.id, id)
      enabled = enabled == "true"

      case EventRules.toggle_rule(scope, rule, !enabled) do
        {:ok, _} ->
          label = if enabled, do: "disabled", else: "enabled"
          {:noreply, socket |> load_page() |> put_flash(:info, "Omen #{label}.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not toggle omen.")}
      end
    end)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    authorize(socket, :configure, fn ->
      scope = socket.assigns.current_scope
      workspace = socket.assigns.workspace
      rule = EventRules.get_rule!(scope, workspace.id, id)

      case EventRules.delete_rule(scope, rule) do
        {:ok, _} ->
          {:noreply, socket |> load_page() |> put_flash(:info, "Omen removed.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not remove omen.")}
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Omens</h1>
        <.link
          :if={@can?.(:configure)}
          navigate={
            ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/event-rules/new"
          }
          class="btn btn-primary btn-sm"
        >
          New Omen
        </.link>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search omens..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>
          No omens defined. Create event rules to trigger actions when events occur.
        </p>
        <p :if={@filter != ""}>No omens match your search.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={rule <- @page.entries}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <.link
                navigate={
                  ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/event-rules/#{rule.id}"
                }
                class="font-medium hover:underline"
              >
                {rule.name}
              </.link>
              <span class="badge badge-ghost badge-xs">{rule.event_type}</span>
              <span class="badge badge-ghost badge-xs">{rule.action_type}</span>
              <span :if={rule.enabled} class="badge badge-success badge-xs">Enabled</span>
              <span :if={!rule.enabled} class="badge badge-neutral badge-xs">Disabled</span>
            </div>
            <div :if={rule.description} class="text-sm text-base-content/60 mt-1 truncate">
              {rule.description}
            </div>
            <div class="text-xs text-base-content/40 mt-1">
              Priority: {rule.priority} | Fired: {rule.fire_count} times
              <span :if={rule.cooldown_s > 0}> | Cooldown: {rule.cooldown_s}s</span>
            </div>
          </div>
          <div class="flex gap-2 flex-shrink-0">
            <button
              :if={@can?.(:configure)}
              phx-click="toggle"
              phx-value-id={rule.id}
              phx-value-enabled={to_string(rule.enabled)}
              class={[
                "btn btn-sm btn-outline",
                rule.enabled && "btn-warning",
                !rule.enabled && "btn-success"
              ]}
            >
              {if rule.enabled, do: "Disable", else: "Enable"}
            </button>
            <.link
              :if={@can?.(:configure)}
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/event-rules/#{rule.id}/edit"
              }
              class="btn btn-ghost btn-sm"
            >
              Edit
            </.link>
            <button
              :if={@can?.(:configure)}
              phx-click={show_confirm("#delete-rule-#{rule.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Delete
            </button>
            <.confirm_modal
              :if={@can?.(:configure)}
              id={"delete-rule-#{rule.id}"}
              title="Delete omen?"
              message="This event rule will be permanently removed."
              confirm_text="Delete"
              on_confirm={JS.push("delete", value: %{id: rule.id})}
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
    page = EventRules.list_rules_paginated(scope, workspace.id, opts)
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
end
