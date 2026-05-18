defmodule Summoner.SkillsFixtures do
  @moduledoc """
  Test helpers for creating skill-related entities.
  """

  alias Summoner.Skills

  def unique_skill_name, do: "skill-#{System.unique_integer([:positive])}"

  def valid_skill_attributes(workspace_id, attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_skill_name(),
      content: "This is test skill content for testing purposes.",
      workspace_id: workspace_id
    })
  end

  def skill_fixture(scope, workspace_id, attrs \\ %{}) do
    {:ok, skill} =
      workspace_id
      |> valid_skill_attributes(attrs)
      |> then(&Skills.create_skill(scope, &1))

    skill
  end
end
