defmodule Summoner.Adapters.Persistence.SwarmsFixtures do
  @moduledoc """
  Test helpers for creating swarm-related entities.
  """

  alias Summoner.Adapters.Persistence.Swarms

  def unique_swarm_name, do: "swarm-#{System.unique_integer([:positive])}"

  def swarm_fixture(scope, workspace_id, attrs \\ %{}) do
    {:ok, swarm} =
      Swarms.create_swarm(
        scope,
        Map.merge(%{name: unique_swarm_name(), workspace_id: workspace_id}, attrs)
      )

    swarm
  end
end
