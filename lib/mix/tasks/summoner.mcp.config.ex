defmodule Mix.Tasks.Summoner.Mcp.Config do
  @moduledoc """
  Generates MCP client configuration for connecting to Summoner.

  Outputs JSON configuration that can be pasted into Claude Code's
  `mcp_servers` config, Cursor settings, or other MCP clients.

  ## Usage

      mix summoner.mcp.config [--url URL] [--transport sse|stdio]

  ## Options

    * `--url` — server URL (default: http://localhost:4000)
    * `--transport` — transport type: `sse` or `stdio` (default: sse)
  """

  use Mix.Task

  @shortdoc "Generate MCP client config for Summoner"

  @impl true
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [url: :string, transport: :string]
      )

    url = opts[:url] || "http://localhost:4000"
    transport = opts[:transport] || "sse"

    config =
      case transport do
        "stdio" ->
          %{
            "mcpServers" => %{
              "summoner" => %{
                "command" => "mix",
                "args" => ["summoner.mcp.stdio"],
                "env" => %{
                  "SUMMONER_TOKEN" => "<your-token-here>",
                  "SUMMONER_WORKSPACE" => "<your-workspace-id>"
                }
              }
            }
          }

        _ ->
          %{
            "mcpServers" => %{
              "summoner" => %{
                "type" => "streamable-http",
                "url" => "#{url}/mcp",
                "headers" => %{
                  "Authorization" => "Bearer <your-token-here>"
                }
              }
            }
          }
      end

    json = Jason.encode!(config, pretty: true)

    Mix.shell().info("""
    Add this to your MCP client configuration:

    #{json}

    Replace <your-token-here> with a valid Summoner API access token.
    """)
  end
end
