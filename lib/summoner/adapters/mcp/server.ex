defmodule Summoner.Adapters.MCP.Server do
  @moduledoc """
  Summoner MCP Server — exposes agents, pipelines, and skills as MCP tools.

  External MCP clients (Claude Code, Cursor, Windsurf) can discover and invoke
  Summoner agents through the standard MCP protocol. Auth is handled at the
  transport layer (Bearer token), and the workspace is derived from the token
  and stored in the frame's assigns.

  ## Tools

  - `invoke_agent` — invoke a Summoner agent with a prompt
  - `list_agents` — list available agents in the workspace
  - `run_pipeline` — trigger a pipeline run
  - `list_pipelines` — list available pipelines
  - `search_skills` — search available skills
  """

  use Anubis.Server,
    name: "summoner",
    version: Mix.Project.config()[:version],
    capabilities: [:tools],
    instructions: """
    Summoner is an AI agent orchestration platform. Use the provided tools to:
    - Invoke agents by name or ID to perform tasks
    - List available agents and their capabilities
    - Run multi-step pipelines (Quests)
    - Search for skills that agents can use
    """

  component(Summoner.Adapters.MCP.Tools.InvokeAgent)
  component(Summoner.Adapters.MCP.Tools.ListAgents)
  component(Summoner.Adapters.MCP.Tools.RunPipeline)
  component(Summoner.Adapters.MCP.Tools.ListPipelines)
  component(Summoner.Adapters.MCP.Tools.SearchSkills)

  @impl true
  def init(_client_info, frame) do
    # The workspace_id and tenant_id are injected via conn.assigns by the
    # MCP auth plug before the Anubis transport plug runs. The session
    # merges transport context assigns into the frame automatically.
    workspace_id = frame.assigns[:current_workspace_id]
    tenant_id = frame.assigns[:current_tenant_id]

    frame =
      frame
      |> assign(:workspace_id, workspace_id)
      |> assign(:tenant_id, tenant_id)

    :telemetry.execute(
      [:summoner, :mcp, :session_started],
      %{system_time: System.system_time()},
      %{workspace_id: workspace_id}
    )

    {:ok, frame}
  end
end
