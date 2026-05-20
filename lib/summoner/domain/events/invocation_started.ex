defmodule Summoner.Domain.Events.InvocationStarted do
  @moduledoc "Published when an invocation begins running."
  @enforce_keys [:workspace_id, :agent_id, :invocation_id]
  defstruct [:workspace_id, :agent_id, :invocation_id]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          agent_id: String.t(),
          invocation_id: String.t()
        }
end
