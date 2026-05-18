defmodule SummonerWeb.SwarmLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.Agents
  alias Summoner.Swarms
  alias Summoner.Swarms.Swarm
  alias Summoner.Workspaces.Policy

  @impl true
  def mount(params, _session, socket) do
    workspace = socket.assigns.workspace

    if Policy.can?(socket.assigns.membership, :configure) do
      scope = socket.assigns.current_scope
      agents = Agents.list_agents(scope, workspace.id)

      {swarm, title} =
        case params["id"] do
          nil ->
            {%Swarm{
               workspace_id: workspace.id,
               members: [],
               mode: :relay
             }, "New Party"}

          id ->
            {Swarms.get_swarm!(scope, workspace.id, id), "Edit Party"}
        end

      changeset = Swarm.changeset(swarm, %{})

      agent_options = Enum.map(agents, fn a -> {a.name, a.id} end)

      socket =
        socket
        |> assign(page_title: "#{title} - #{workspace.name}")
        |> assign(
          swarm: swarm,
          form: to_form(changeset),
          title: title,
          editing: swarm.id != nil,
          agent_options: agent_options,
          members: swarm.members,
          mode: swarm.mode || :relay
        )
        |> assign(
          breadcrumbs: [
            {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
            {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
            {"Partys", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/parties"},
            {title, nil}
          ]
        )

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to do that.")
       |> redirect(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}")}
    end
  end

  @impl true
  def handle_event("validate", %{"swarm" => params}, socket) do
    changeset =
      socket.assigns.swarm
      |> Swarm.changeset(params)
      |> Map.put(:action, :validate)

    mode = String.to_existing_atom(params["mode"] || "relay")
    {:noreply, assign(socket, form: to_form(changeset), mode: mode)}
  end

  @impl true
  def handle_event("save", %{"swarm" => params}, socket) do
    if socket.assigns.editing do
      update_swarm(socket, params)
    else
      create_swarm(socket, params)
    end
  end

  @impl true
  def handle_event("add_member", %{"agent_id" => agent_id}, socket) when agent_id != "" do
    scope = socket.assigns.current_scope
    swarm = socket.assigns.swarm

    if swarm.id do
      case Swarms.add_member(scope, %{swarm_id: swarm.id, agent_id: agent_id}) do
        {:ok, _member} ->
          members = Swarms.list_members(swarm.id)

          {:noreply,
           socket |> assign(members: members) |> put_flash(:info, "Summon joined the party.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not add summon.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Save the party first before adding members.")}
    end
  end

  def handle_event("add_member", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("remove_member", %{"id" => member_id}, socket) do
    scope = socket.assigns.current_scope
    swarm = socket.assigns.swarm

    member = Enum.find(socket.assigns.members, &(&1.id == member_id))

    if member do
      case Swarms.remove_member(scope, member) do
        {:ok, _} ->
          members = Swarms.list_members(swarm.id)

          {:noreply,
           socket |> assign(members: members) |> put_flash(:info, "Summon removed from party.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not remove summon.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reorder_members", %{"ids" => ids}, socket) when is_list(ids) do
    scope = socket.assigns.current_scope
    swarm = socket.assigns.swarm

    if swarm.id do
      case Swarms.reorder_members(scope, swarm.id, ids) do
        {:ok, members} ->
          {:noreply, assign(socket, members: members)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not reorder members.")}
      end
    else
      {:noreply, socket}
    end
  end

  defp create_swarm(socket, params) do
    workspace = socket.assigns.workspace
    params = Map.put(params, "workspace_id", workspace.id)

    case Swarms.create_swarm(socket.assigns.current_scope, params) do
      {:ok, swarm} ->
        {:noreply,
         socket
         |> put_flash(:info, "Party formed. Add members below.")
         |> push_navigate(
           to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/parties/#{swarm.id}/edit"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_swarm(socket, params) do
    workspace = socket.assigns.workspace

    case Swarms.update_swarm(socket.assigns.current_scope, socket.assigns.swarm, params) do
      {:ok, _swarm} ->
        {:noreply,
         socket
         |> put_flash(:info, "Party updated.")
         |> push_navigate(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/parties")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <h1 class="text-2xl font-bold">{@title}</h1>

      <.form for={@form} id="swarm-form" phx-submit="save" phx-change="validate" class="space-y-4">
        <.input field={@form[:name]} type="text" label="Name" required phx-debounce="300" />
        <.text_editor
          field={@form[:description]}
          label="Description"
          placeholder="Describe the party's purpose..."
        />

        <.input
          field={@form[:mode]}
          type="select"
          label="Turn Routing Mode"
          options={[
            {"Round Robin — summons take turns in order", "round_robin"},
            {"Relay — @callname routing", "relay"},
            {"Summoning — coordinator decides", "directed"}
          ]}
        />

        <div class="text-xs text-base-content/50 -mt-2 ml-1">
          <p :if={@mode == :round_robin}>
            Each summon speaks in member order, cycling continuously until one calls done or max turns is reached.
          </p>
          <p :if={@mode == :relay}>
            Summons hand off by writing @callname in their response. Stops when no relay target is found.
          </p>
          <p :if={@mode == :directed}>
            A coordinator summon analyzes the conversation and decides who speaks next.
          </p>
        </div>

        <div :if={@mode == :directed}>
          <.input
            field={@form[:coordinator_agent_id]}
            type="select"
            label="Coordinator Summon"
            prompt="Select coordinator..."
            options={@agent_options}
          />
          <p class="text-xs text-base-content/50 mt-1">
            The coordinator decides which summon speaks next.
          </p>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:max_turns]}
            type="number"
            label="Max Turns"
            min="1"
            max="100"
          />
        </div>

        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/parties"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Party", else: "Form Party"}
          </.button>
        </div>
      </.form>

      <%!-- Member management (only when editing) --%>
      <div :if={@editing} class="space-y-4">
        <h2 class="text-lg font-semibold">Members</h2>

        <div :if={@members == []} class="text-sm text-base-content/60">
          No members yet. Add summons to this party.
        </div>

        <div class="space-y-2" id="member-list" phx-hook="Sortable">
          <div
            :for={member <- @members}
            data-sortable-id={member.id}
            draggable="true"
            class="flex items-center justify-between p-3 bg-base-200 rounded-lg cursor-grab active:cursor-grabbing"
          >
            <div class="flex items-center gap-3 min-w-0 flex-1">
              <span class="hero-bars-3 size-5 text-base-content/30 flex-shrink-0"></span>
              <div class="min-w-0">
                <div class="flex items-center gap-2">
                  <.link
                    navigate={
                      ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/summons/#{member.agent.id}"
                    }
                    class="font-medium link link-hover truncate"
                  >
                    {member.agent.name}
                  </.link>
                  <span class={[
                    "badge badge-sm",
                    member.agent.role == :worker && "badge-info",
                    member.agent.role == :autonomous && "badge-success"
                  ]}>
                    {member.agent.role}
                  </span>
                </div>
                <div class="text-sm text-base-content/60 truncate">
                  {member.agent.model}
                </div>
              </div>
            </div>
            <button
              phx-click={show_confirm("#remove-swarm-member-#{member.id}")}
              class="btn btn-error btn-xs btn-outline"
            >
              Remove
            </button>
            <.confirm_modal
              id={"remove-swarm-member-#{member.id}"}
              title="Remove summon?"
              message="This summon will be removed from the party."
              confirm_text="Remove"
              on_confirm={JS.push("remove_member", value: %{id: member.id})}
            />
          </div>
        </div>

        <form phx-submit="add_member" class="flex items-end gap-2">
          <div class="form-control flex-1">
            <label class="label">
              <span class="label-text">Add Summon</span>
            </label>
            <select name="agent_id" class="select select-bordered select-sm w-full">
              <option value="">Select a summon</option>
              {Phoenix.HTML.Form.options_for_select(@agent_options, nil)}
            </select>
          </div>
          <button type="submit" class="btn btn-secondary btn-sm">Add</button>
        </form>
      </div>
    </div>
    """
  end
end
