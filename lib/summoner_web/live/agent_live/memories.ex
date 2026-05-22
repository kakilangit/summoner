defmodule SummonerWeb.AgentLive.Memories do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Domain.Schemas.AgentMemory
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.AgentMemories
  alias Summoner.Services.Embedding

  @sort_options [
    {"Confidence", :confidence},
    {"Type", :type},
    {"Created", :inserted_at},
    {"Last Accessed", :last_accessed_at}
  ]
  @default_sort_by :inserted_at
  @default_sort_dir :desc
  @filter_fields [:content]

  @type_options [
    {"All", nil},
    {"Fact", :fact},
    {"Preference", :preference},
    {"Procedure", :procedure},
    {"Correction", :correction}
  ]

  @impl true
  def mount(%{"id" => agent_id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope
    agent = Agents.get_agent!(scope, workspace.id, agent_id)

    socket =
      socket
      |> assign(
        page_title: "Memories - #{agent.name}",
        agent: agent,
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        type_filter: nil,
        sort_options: @sort_options,
        type_options: @type_options,
        editing_memory: nil,
        edit_form: nil
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Summons",
           ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/agents"},
          {agent.name,
           ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/agents/#{agent.id}"},
          {"Memories", nil}
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
  def handle_event("filter_type", %{"type" => ""}, socket) do
    {:noreply, socket |> assign(type_filter: nil) |> load_page()}
  end

  @impl true
  def handle_event("filter_type", %{"type" => type}, socket) do
    {:noreply, socket |> assign(type_filter: String.to_existing_atom(type)) |> load_page()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    authorize(socket, :configure, fn ->
      memory = AgentMemories.get_memory!(id)

      case AgentMemories.delete_memory(memory) do
        {:ok, _} ->
          {:noreply, socket |> load_page() |> put_flash(:info, "Memory deleted.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not delete memory.")}
      end
    end)
  end

  @impl true
  def handle_event("bulk_delete_below", %{"threshold" => threshold}, socket) do
    authorize(socket, :configure, fn ->
      {threshold, _} = Float.parse(threshold)
      {count, _} = AgentMemories.prune_below(socket.assigns.agent.id, threshold)

      {:noreply,
       socket
       |> load_page()
       |> put_flash(:info, "Pruned #{count} memories below #{threshold} confidence.")}
    end)
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    memory = AgentMemories.get_memory!(id)
    changeset = AgentMemory.changeset(memory, %{})

    {:noreply,
     assign(socket,
       editing_memory: memory,
       edit_form: to_form(changeset)
     )}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_memory: nil, edit_form: nil)}
  end

  @impl true
  def handle_event("validate_edit", %{"agent_memory" => params}, socket) do
    changeset =
      socket.assigns.editing_memory
      |> AgentMemory.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, edit_form: to_form(changeset))}
  end

  @impl true
  def handle_event("save_edit", %{"agent_memory" => params}, socket) do
    authorize(socket, :configure, fn ->
      memory = socket.assigns.editing_memory
      content_changed = params["content"] != memory.content

      case AgentMemories.update_memory(memory, params) do
        {:ok, updated} ->
          if content_changed do
            re_embed_async(socket.assigns.workspace.id, updated)
          end

          {:noreply,
           socket
           |> assign(editing_memory: nil, edit_form: nil)
           |> load_page()
           |> put_flash(:info, "Memory updated.")}

        {:error, changeset} ->
          {:noreply, assign(socket, edit_form: to_form(changeset))}
      end
    end)
  end

  defp load_page(socket) do
    %{agent: agent} = socket.assigns

    opts =
      [
        page: Map.get(socket.assigns, :page_num, get_in(socket.assigns, [:page, :page])) || 1,
        sort_by: socket.assigns.sort_by,
        sort_dir: socket.assigns.sort_dir,
        filter: socket.assigns.filter,
        filter_fields: @filter_fields
      ]
      |> maybe_add_type(socket.assigns.type_filter)

    page = AgentMemories.list_memories_paginated(agent.id, opts)
    assign(socket, page: page)
  end

  defp maybe_add_type(opts, nil), do: opts
  defp maybe_add_type(opts, type), do: Keyword.put(opts, :type, type)

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  defp re_embed_async(workspace_id, memory) do
    Task.Supervisor.start_child(Summoner.TaskSupervisor, fn ->
      with {:ok, vector} <- Embedding.embed(workspace_id, memory.content) do
        AgentMemories.update_embedding(memory, vector)
      end
    end)
  end

  defp confidence_color(confidence) when confidence >= 0.7, do: "text-success"
  defp confidence_color(confidence) when confidence >= 0.4, do: "text-warning"
  defp confidence_color(_), do: "text-error"

  defp type_badge_class(:fact), do: "badge-info"
  defp type_badge_class(:preference), do: "badge-accent"
  defp type_badge_class(:procedure), do: "badge-success"
  defp type_badge_class(:correction), do: "badge-warning"

  defp to_float(val) when is_float(val), do: val
  defp to_float(val) when is_integer(val), do: val / 1
  defp to_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end
  defp to_float(_), do: 0.0

  defp format_confidence(confidence) do
    confidence
    |> Kernel.*(100)
    |> Float.round(1)
    |> to_string()
    |> Kernel.<>("%")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Memories — {@agent.name}</h1>
        <div :if={@can?.(:configure)} class="flex gap-2">
          <button
            phx-click={show_confirm("#bulk-prune")}
            class="btn btn-warning btn-sm btn-outline"
          >
            Prune Low Confidence
          </button>
          <.confirm_modal
            id="bulk-prune"
            title="Prune low confidence memories?"
            message="Delete all memories below the confidence threshold. This cannot be undone."
            confirm_text="Prune"
            on_confirm={JS.push("bulk_delete_below", value: %{threshold: "0.3"})}
          />
        </div>
      </div>

      <div class="flex gap-4 items-end">
        <div class="flex-1">
          <.list_controls
            filter={@filter}
            sort_by={@sort_by}
            sort_dir={@sort_dir}
            sort_options={@sort_options}
            placeholder="Search memories..."
          />
        </div>
        <div class="form-control">
          <select
            class="select select-bordered select-sm"
            phx-change="filter_type"
            name="type"
          >
            <option :for={{label, value} <- @type_options} value={value || ""} selected={@type_filter == value}>
              {label}
            </option>
          </select>
        </div>
      </div>

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == "" and is_nil(@type_filter)}>No memories yet. This agent hasn't learned anything.</p>
        <p :if={@filter != "" or not is_nil(@type_filter)}>No memories match your filters.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={memory <- @page.entries}
          class="p-4 bg-base-200 rounded-lg space-y-2"
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class={["badge badge-sm", type_badge_class(memory.type)]}>
                {memory.type}
              </span>
              <span class={["font-mono text-sm", confidence_color(memory.confidence)]}>
                {format_confidence(memory.confidence)}
              </span>
              <span class="text-xs text-base-content/50">
                accessed {memory.access_count}x
              </span>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-xs text-base-content/50">
                {Calendar.strftime(memory.inserted_at, "%Y-%m-%d %H:%M")}
              </span>
              <button
                :if={@can?.(:configure)}
                phx-click="edit"
                phx-value-id={memory.id}
                class="btn btn-ghost btn-xs"
              >
                Edit
              </button>
              <button
                :if={@can?.(:configure)}
                phx-click={show_confirm("#delete-memory-#{memory.id}")}
                class="btn btn-error btn-xs btn-outline"
              >
                Delete
              </button>
              <.confirm_modal
                :if={@can?.(:configure)}
                id={"delete-memory-#{memory.id}"}
                title="Delete memory?"
                message="This memory will be permanently removed."
                confirm_text="Delete"
                on_confirm={JS.push("delete", value: %{id: memory.id})}
              />
            </div>
          </div>
          <div class="text-sm whitespace-pre-wrap">{memory.content}</div>
        </div>
      </div>

      <.pagination page={@page} />

      <div :if={@editing_memory} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Edit Memory</h3>
          <.form for={@edit_form} phx-change="validate_edit" phx-submit="save_edit" class="space-y-4 mt-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Content</span></label>
              <textarea
                name={@edit_form[:content].name}
                class="textarea textarea-bordered h-32"
                phx-debounce="300"
              >{Phoenix.HTML.Form.normalize_value("textarea", @edit_form[:content].value)}</textarea>
              <span
                :for={msg <- Enum.map(@edit_form[:content].errors, &translate_error/1)}
                class="text-error text-sm"
              >
                {msg}
              </span>
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Confidence</span></label>
              <input
                type="range"
                name={@edit_form[:confidence].name}
                value={@edit_form[:confidence].value}
                min="0"
                max="1"
                step="0.05"
                class="range range-sm"
              />
              <div class="text-sm text-center mt-1">
                {format_confidence(@edit_form[:confidence].value |> to_float())}
              </div>
            </div>
            <div class="modal-action">
              <button type="button" phx-click="cancel_edit" class="btn">Cancel</button>
              <button type="submit" class="btn btn-primary">Save</button>
            </div>
          </.form>
        </div>
        <div class="modal-backdrop" phx-click="cancel_edit"></div>
      </div>
    </div>
    """
  end
end
