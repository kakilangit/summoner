defmodule Summoner.MCPFixtures do
  @moduledoc """
  Test helpers for creating MCP-related entities.
  """

  alias Summoner.MCP

  def unique_mcp_server_name, do: "mcp-server-#{System.unique_integer([:positive])}"

  def valid_mcp_server_attributes(workspace_id, attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_mcp_server_name(),
      transport: :stdio,
      command_or_url: "/usr/bin/echo",
      config: %{},
      workspace_id: workspace_id
    })
  end

  def mcp_server_fixture(scope, workspace_id, attrs \\ %{}) do
    {:ok, server} =
      workspace_id
      |> valid_mcp_server_attributes(attrs)
      |> then(&MCP.create_server(scope, &1))

    server
  end
end
