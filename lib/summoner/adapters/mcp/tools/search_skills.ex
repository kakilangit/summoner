defmodule Summoner.Adapters.MCP.Tools.SearchSkills do
  @moduledoc "Search available skills by keyword."

  use Anubis.Server.Component, type: :tool

  alias Summoner.Domain.Schemas.Scope
  alias Summoner.Ports.Persistence.Skills

  schema do
    field :query, :string, required: true
    field :category, :string, required: false
  end

  @impl true
  def execute(args, frame) do
    workspace_id = frame.assigns[:workspace_id]
    tenant_id = frame.assigns[:tenant_id]
    scope = %Scope{user: nil}

    skills = Skills.list_skills(scope, workspace_id, tenant_id)

    filtered =
      skills
      |> filter_by_query(args.query)
      |> maybe_filter_category(args[:category])

    items =
      Enum.map(filtered, fn s ->
        %{
          id: s.id,
          name: s.name,
          description: s.description,
          category: s.category
        }
      end)

    {:reply, Jason.encode!(%{skills: items, count: length(items)}), frame}
  end

  defp filter_by_query(skills, query) do
    q = String.downcase(query)

    Enum.filter(skills, fn s ->
      String.contains?(String.downcase(s.name || ""), q) or
        String.contains?(String.downcase(s.description || ""), q)
    end)
  end

  defp maybe_filter_category(skills, nil), do: skills
  defp maybe_filter_category(skills, ""), do: skills

  defp maybe_filter_category(skills, category) do
    Enum.filter(skills, &(&1.category == category))
  end
end
