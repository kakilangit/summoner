defmodule Summoner.Adapters.Persistence.AgentMemoriesFixtures do
  @moduledoc "Test helpers for creating agent memory entities."

  alias Summoner.Ports.Persistence.AgentMemories

  def valid_memory_attributes(agent_id, workspace_id, attrs \\ %{}) do
    Enum.into(attrs, %{
      content: "Memory content #{System.unique_integer([:positive])}",
      type: :fact,
      agent_id: agent_id,
      workspace_id: workspace_id,
      confidence: 1.0
    })
  end

  def agent_memory_fixture(agent_id, workspace_id, attrs \\ %{}) do
    {:ok, memory} =
      agent_id
      |> valid_memory_attributes(workspace_id, attrs)
      |> AgentMemories.create_memory()

    memory
  end
end
