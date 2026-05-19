defmodule Summoner.Domain.Events.SwarmDone do
  @moduledoc "Published when a swarm turn cycle completes."
  @enforce_keys [:workspace_id, :swarm_id, :conversation_id, :summary]
  defstruct [:workspace_id, :swarm_id, :conversation_id, :summary]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          swarm_id: String.t(),
          conversation_id: String.t(),
          summary: String.t()
        }
end
