defmodule SummonerWeb.SwarmLive.Show do
  use SummonerWeb, :live_view

  import SummonerWeb.SwarmLive.Helpers

  alias Summoner.Agents
  alias Summoner.Swarms

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope
    swarm = Swarms.get_swarm!(scope, workspace.id, id)

    socket =
      socket
      |> assign(page_title: "#{swarm.name} - #{workspace.name}")
      |> assign(swarm: swarm)
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/realms/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Partys", ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}/parties"},
          {swarm.name, nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("change_model", %{"agent_id" => agent_id, "model" => model}, socket) do
    scope = socket.assigns.current_scope
    swarm = socket.assigns.swarm

    case find_agent(swarm, agent_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Summon not found in party.")}

      agent ->
        switch_member_model(socket, scope, swarm, agent, model)
    end
  end

  defp find_agent(swarm, agent_id) do
    cond do
      swarm.coordinator_agent && swarm.coordinator_agent.id == agent_id ->
        swarm.coordinator_agent

      member = Enum.find(swarm.members, &(&1.agent.id == agent_id)) ->
        member.agent

      true ->
        nil
    end
  end

  defp switch_member_model(socket, scope, swarm, agent, model) do
    case Agents.update_agent(scope, agent, %{model: model}) do
      {:ok, _} ->
        swarm = Swarms.get_swarm!(scope, socket.assigns.workspace.id, swarm.id)

        {:noreply,
         socket
         |> assign(swarm: swarm)
         |> put_flash(
           :info,
           "Spirit switched to #{SummonerWeb.CoreComponents.short_model_name(model)}"
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not switch spirit.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">{@swarm.name}</h1>
        <div class="flex gap-2">
          <.link
            :if={length(@swarm.members) > 0}
            navigate={
              ~p"/realms/#{@workspace.tenant_id}/realms/#{@workspace.id}/parties/#{@swarm.id}/channels"
            }
            class="btn btn-primary btn-sm"
          >
            Channels
          </.link>
          <.link
            navigate={
              ~p"/realms/#{@workspace.tenant_id}/realms/#{@workspace.id}/parties/#{@swarm.id}/edit"
            }
            class="btn btn-ghost btn-sm"
          >
            Edit
          </.link>
        </div>
      </div>

      <div class="space-y-4">
        <div class="flex items-center gap-2">
          <span class={mode_badge_class(@swarm.mode)}>
            <span class={mode_icon(@swarm.mode)}></span>
            {mode_label(@swarm.mode)}
          </span>
          <span class="text-sm text-base-content/60">
            {length(@swarm.members)} member(s)
          </span>
        </div>

        <div :if={@swarm.description} class="collapse collapse-arrow bg-base-200">
          <input type="checkbox" checked />
          <div class="collapse-title text-sm font-medium">Description</div>
          <div class="collapse-content text-sm whitespace-pre-wrap">{@swarm.description}</div>
        </div>

        <div
          :if={@swarm.mode == :directed && @swarm.coordinator_agent}
          class="flex items-center gap-2 text-sm"
        >
          <span class="text-base-content/60">Coordinator:</span>
          <.link
            navigate={
              ~p"/realms/#{@workspace.tenant_id}/realms/#{@workspace.id}/summons/#{@swarm.coordinator_agent.id}"
            }
            class="font-medium link link-hover"
          >
            {@swarm.coordinator_agent.name}
          </.link>
          <.model_switcher agent={@swarm.coordinator_agent} id="coordinator-model" />
        </div>

        <div class="space-y-2">
          <h2 class="text-sm font-medium">Members</h2>
          <div :if={@swarm.members == []} class="text-sm text-base-content/60">
            No members yet.
          </div>
          <div
            :for={member <- @swarm.members}
            class="flex items-center gap-3 p-3 bg-base-200 rounded-lg"
          >
            <.link
              navigate={
                ~p"/realms/#{@workspace.tenant_id}/realms/#{@workspace.id}/summons/#{member.agent.id}"
              }
              class="font-medium link link-hover"
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
            <.model_switcher agent={member.agent} id={"member-model-#{member.id}"} />
          </div>
        </div>

        <div class="collapse collapse-arrow bg-base-200">
          <input type="checkbox" />
          <div class="collapse-title font-medium text-sm">Settings</div>
          <div class="collapse-content">
            <div class="grid grid-cols-2 gap-2 text-sm">
              <div class="text-base-content/60">Max Turns</div>
              <div>{@swarm.max_turns}</div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
