defmodule Summoner.Services.A2A.SkillResolver do
  @moduledoc """
  Resolves which A2A skill to invoke based on the user message and agent card.

  For agents with skills, attempts to match the message to a skill.
  If no match is found or the agent has no skills, returns nil (free-form text).
  """

  @doc """
  Given a cached agent card and a user message, returns the best matching
  skill data map or nil.

  Uses keyword matching against skill names, descriptions, tags, and examples.
  Returns `%{"skill" => skill_id}` or nil.
  """
  def resolve(nil, _message), do: nil
  def resolve(%{"skills" => []}, _message), do: nil
  def resolve(%{"skills" => nil}, _message), do: nil

  def resolve(%{"skills" => skills}, message) when is_list(skills) and is_binary(message) do
    case find_best_match(skills, message) do
      nil -> nil
      %{"id" => skill_id} -> %{"skill" => skill_id}
    end
  end

  def resolve(_, _), do: nil

  @doc """
  Wraps a known skill ID as a skill data map.
  Used when the skill is explicitly specified (e.g., from pipeline stage config).
  """
  def for_skill(nil), do: nil
  def for_skill(skill_id) when is_binary(skill_id), do: %{"skill" => skill_id}

  defp find_best_match(skills, message) do
    lowered = String.downcase(message)

    skills
    |> Enum.map(fn skill -> {skill, score_skill(skill, lowered)} end)
    |> Enum.filter(fn {_skill, score} -> score > 0 end)
    |> Enum.max_by(fn {_skill, score} -> score end, fn -> nil end)
    |> case do
      {skill, _score} -> skill
      # Fallback to first skill if no match (single-skill agents)
      nil -> List.first(skills)
    end
  end

  defp score_skill(skill, lowered_message) do
    name_score = if match_text?(Map.get(skill, "name", ""), lowered_message), do: 3, else: 0

    desc_score =
      if match_text?(Map.get(skill, "description", ""), lowered_message), do: 2, else: 0

    tag_score =
      skill
      |> Map.get("tags", [])
      |> Enum.count(&match_text?(&1, lowered_message))

    example_score =
      skill
      |> Map.get("examples", [])
      |> Enum.count(&(String.jaro_distance(String.downcase(&1), lowered_message) > 0.6))
      |> then(&(&1 * 2))

    name_score + desc_score + tag_score + example_score
  end

  defp match_text?(text, lowered_message) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split(~r/[\s,_-]+/)
    |> Enum.filter(&(String.length(&1) > 3))
    |> Enum.any?(&String.contains?(lowered_message, &1))
  end

  defp match_text?(_, _), do: false
end
