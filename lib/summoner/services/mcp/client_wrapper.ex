defmodule Summoner.Services.MCP.ClientWrapper do
  @moduledoc """
  Thin wrapper that starts an Anubis MCP client supervisor under
  `Summoner.McpSupervisor`.

  Provides:
  - Registry-based lookup via `{workspace_id, server_id}`
  - `child_spec/1` compatible with DynamicSupervisor

  The underlying `Anubis.Client` supervisor manages the client
  GenServer and transport process. We override the child_spec
  to use `:temporary` restart since MCP clients are user-toggled.
  """

  @doc """
  Returns a child spec for starting an Anubis.Client supervisor
  under a DynamicSupervisor with `:temporary` restart.
  """
  def child_spec({server, anubis_opts}) do
    key = {server.workspace_id, server.id}

    %{
      id: key,
      start: {Anubis.Client.Supervisor, :start_link, [anubis_opts]},
      type: :supervisor,
      restart: :temporary
    }
  end
end
