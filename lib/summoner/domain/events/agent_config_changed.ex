defmodule Summoner.Domain.Events.AgentConfigChanged do
  @moduledoc "Published when an agent's tool/MCP configuration changes."
  @enforce_keys [:agent_id]
  defstruct [:agent_id]
  @type t :: %__MODULE__{agent_id: String.t()}
end
