defmodule Summoner.Adapters.Persistence.AgentsFixtures do
  @moduledoc """
  Test helpers for creating agent-related entities.
  """

  alias Summoner.Adapters.Persistence.Agents

  def unique_agent_name, do: "agent-#{System.unique_integer([:positive])}"

  def valid_agent_attributes(workspace_id, provider_id, attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_agent_name(),
      model: "test-model",
      role: :autonomous,
      workspace_id: workspace_id,
      provider_id: provider_id
    })
  end

  def agent_fixture(scope, workspace_id, provider_id, attrs \\ %{}) do
    {:ok, agent} =
      workspace_id
      |> valid_agent_attributes(provider_id, attrs)
      |> then(&Agents.create_agent(scope, &1))

    agent
  end
end
