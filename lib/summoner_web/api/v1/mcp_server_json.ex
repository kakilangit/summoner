defmodule SummonerWeb.API.V1.McpServerJSON do
  @moduledoc "JSON rendering for MCP servers."

  def index(%{servers: servers}) do
    %{data: Enum.map(servers, &server_data/1)}
  end

  def show(%{server: server}) do
    %{data: server_data(server)}
  end

  defp server_data(s) do
    %{
      id: s.id,
      name: s.name,
      transport: s.transport,
      command_or_url: s.command_or_url,
      config: s.config,
      workspace_id: s.workspace_id,
      tenant_id: s.tenant_id,
      inserted_at: s.inserted_at,
      updated_at: s.updated_at
    }
  end
end
