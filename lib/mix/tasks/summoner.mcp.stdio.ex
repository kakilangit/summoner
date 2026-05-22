defmodule Mix.Tasks.Summoner.Mcp.Stdio do
  @moduledoc """
  Starts the Summoner MCP server in stdio transport mode.

  Reads JSON-RPC from stdin, writes responses to stdout.
  Useful for local development with Claude Code or other MCP clients.

  ## Usage

      mix summoner.mcp.stdio [--workspace WORKSPACE_ID] [--token TOKEN]

  ## Options

    * `--workspace` — workspace ID to scope tool calls to
    * `--token` — access token (alternative to setting SUMMONER_TOKEN env var)
  """

  use Mix.Task

  @shortdoc "Start Summoner MCP server in stdio mode"

  @impl true
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [workspace: :string, token: :string]
      )

    # Disable the default streamable_http MCP server
    Application.put_env(:summoner, :start_mcp_server, false)
    Mix.Task.run("app.start")

    _workspace_id = opts[:workspace] || System.get_env("SUMMONER_WORKSPACE")
    _token = opts[:token] || System.get_env("SUMMONER_TOKEN")

    # Start a separate MCP server with stdio transport
    {:ok, _pid} =
      Anubis.Server.Supervisor.start_link(Summoner.Adapters.MCP.Server,
        transport: :stdio,
        name: Summoner.Adapters.MCP.StdioServer
      )

    # The stdio server reads from stdin — keep alive until EOF
    Process.sleep(:infinity)
  end
end
