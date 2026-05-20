defmodule Summoner.Adapters.Persistence.OrchestrationFixtures do
  @moduledoc """
  Test helpers for creating orchestration-related entities.
  """

  alias Summoner.Adapters.Persistence.Orchestration

  def valid_invocation_attributes(workspace_id, agent_id, attrs \\ %{}) do
    Enum.into(attrs, %{
      workspace_id: workspace_id,
      agent_id: agent_id
    })
  end

  def invocation_fixture(scope, workspace_id, agent_id, attrs \\ %{}) do
    {:ok, invocation} =
      workspace_id
      |> valid_invocation_attributes(agent_id, attrs)
      |> then(&Orchestration.create_invocation(scope, &1))

    invocation
  end

  def subtask_fixture(invocation, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        description: "Test subtask",
        position: Map.get(attrs, :position, 0)
      })

    {:ok, [subtask]} = Orchestration.create_subtasks(invocation, [attrs])
    subtask
  end
end
