defmodule SummonerWeb.AgentLive.Skills do
  use SummonerWeb, :live_view

  alias Summoner.Agents
  alias Summoner.Skills

  @impl true
  def mount(%{"id" => agent_id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope

    agent = Agents.get_agent!(scope, workspace.id, agent_id)
    all_skills = Skills.list_skills(scope, workspace.id, workspace.tenant_id)
    equipped = Skills.list_equipped_skills(scope, agent.id)
    equipped_ids = MapSet.new(equipped, & &1.id)

    socket =
      socket
      |> assign(page_title: "Grimoire - #{agent.name}")
      |> assign(
        agent: agent,
        all_skills: all_skills,
        equipped_ids: equipped_ids
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/realms/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Summons", ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}/summons"},
          {agent.name,
           ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}/summons/#{agent.id}"},
          {"Grimoire", nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("equip", %{"skill-id" => skill_id}, socket) do
    scope = socket.assigns.current_scope
    agent = socket.assigns.agent

    case Skills.equip_skill(scope, %{agent_id: agent.id, skill_id: skill_id}) do
      {:ok, _} ->
        equipped = Skills.list_equipped_skills(scope, agent.id)
        equipped_ids = MapSet.new(equipped, & &1.id)
        {:noreply, assign(socket, equipped_ids: equipped_ids)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not equip spell.")}
    end
  end

  @impl true
  def handle_event("unequip", %{"skill-id" => skill_id}, socket) do
    scope = socket.assigns.current_scope
    agent = socket.assigns.agent

    case Skills.unequip_skill(scope, agent.id, skill_id) do
      {:ok, _} ->
        equipped = Skills.list_equipped_skills(scope, agent.id)
        equipped_ids = MapSet.new(equipped, & &1.id)
        {:noreply, assign(socket, equipped_ids: equipped_ids)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not unequip spell.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">Grimoire for {@agent.name}</h1>

      <div :if={@all_skills == []} class="text-center py-12 text-base-content/60">
        <p>
          No spells available.
          <.link
            navigate={~p"/realms/#{@workspace.tenant_id}/realms/#{@workspace.id}/spells/new"}
            class="link"
          >
            Add one first.
          </.link>
        </p>
      </div>

      <div class="space-y-2">
        <div
          :for={skill <- @all_skills}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span class="font-medium">{skill.name}</span>
              <span :if={skill.embedding} class="badge badge-sm badge-success">embedded</span>
            </div>
            <div class="text-sm text-base-content/60 truncate max-w-md">
              {String.slice(skill.content, 0, 100)}
            </div>
          </div>
          <div>
            <button
              :if={MapSet.member?(@equipped_ids, skill.id)}
              phx-click="unequip"
              phx-value-skill-id={skill.id}
              class="btn btn-sm btn-error btn-outline"
            >
              Unequip
            </button>
            <button
              :if={!MapSet.member?(@equipped_ids, skill.id)}
              phx-click="equip"
              phx-value-skill-id={skill.id}
              class="btn btn-sm btn-primary btn-outline"
            >
              Equip
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
