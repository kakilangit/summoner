defmodule Summoner.Events.SwarmTimeout do
  @moduledoc "Published when an agent times out during a swarm turn."
  @enforce_keys [:workspace_id, :swarm_id, :conversation_id, :agent_id]
  defstruct [:workspace_id, :swarm_id, :conversation_id, :agent_id]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          swarm_id: String.t(),
          conversation_id: String.t(),
          agent_id: String.t()
        }
end
