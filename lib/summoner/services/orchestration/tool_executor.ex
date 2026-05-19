defmodule Summoner.Services.Orchestration.ToolExecutor do
  @moduledoc """
  Behaviour for executing tool calls during the ReAct loop.

  The MCP bridge (Phase 1.15) will provide the concrete implementation.
  For now, a stub implementation is used in tests.
  """

  @type tool_call :: %{
          id: String.t(),
          function: %{
            name: String.t(),
            arguments: String.t()
          }
        }

  @type context :: %{agent_id: binary(), workspace_id: binary()}

  @callback execute(tool_call :: tool_call(), context :: context()) ::
              {:ok, String.t()} | {:error, String.t()}
end
