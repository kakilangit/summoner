defmodule SummonerWeb.API.V1.SwarmJSON do
  @moduledoc "JSON rendering for swarms."

  import SummonerWeb.API.PaginationJSON

  def index(%{page: page}) do
    %{items: Enum.map(page.entries, &swarm_data/1), meta: page_meta(page)}
  end

  def show(%{swarm: swarm}) do
    swarm_data(swarm)
  end

  defp swarm_data(s) do
    base = %{
      id: s.id,
      name: s.name,
      description: s.description,
      mode: s.mode,
      max_turns: s.max_turns,
      workspace_id: s.workspace_id,
      coordinator_agent_id: s.coordinator_agent_id,
      inserted_at: s.inserted_at,
      updated_at: s.updated_at
    }

    case s do
      %{members: members} when is_list(members) ->
        Map.put(base, :members, Enum.map(members, &member_data/1))

      _ ->
        base
    end
  end

  defp member_data(m) do
    %{
      id: m.id,
      position: m.position,
      agent_id: m.agent_id,
      swarm_id: m.swarm_id,
      inserted_at: m.inserted_at
    }
  end
end
