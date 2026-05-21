defmodule SummonerWeb.API.V1.SkillJSON do
  @moduledoc "JSON rendering for skills. Embeddings are excluded."

  import SummonerWeb.API.PaginationJSON

  def index(%{page: page}) do
    %{data: Enum.map(page.entries, &skill_data/1), meta: page_meta(page)}
  end

  def show(%{skill: skill}) do
    %{data: skill_data(skill)}
  end

  defp skill_data(s) do
    %{
      id: s.id,
      name: s.name,
      content: s.content,
      workspace_id: s.workspace_id,
      tenant_id: s.tenant_id,
      inserted_at: s.inserted_at,
      updated_at: s.updated_at
    }
  end
end
