defmodule Summoner.Domain.Schemas.AgentMcpServer do
  @moduledoc """
  Join schema linking Agents to MCP servers (the "Magic Circle" allowlist).

  An Agent can only invoke tools from MCP servers that are explicitly
  equipped via this join table.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  schema "agent_mcp_servers" do
    field :env, :map, default: %{}
    field :enabled, :boolean, default: true

    belongs_to :agent, Summoner.Domain.Schemas.Agent
    belongs_to :mcp_server, Summoner.Domain.Schemas.McpServer

    timestamps()
  end

  def changeset(agent_mcp_server, attrs) do
    agent_mcp_server
    |> cast(attrs, [:agent_id, :mcp_server_id, :env, :enabled])
    |> validate_required([:agent_id, :mcp_server_id])
    |> unique_constraint([:agent_id, :mcp_server_id])
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:mcp_server_id)
  end
end
