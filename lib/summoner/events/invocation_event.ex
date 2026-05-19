defmodule Summoner.Events.InvocationEvent do
  @moduledoc "Published for tool lifecycle events during an invocation."
  @enforce_keys [:workspace_id, :agent_id, :invocation_id, :event]
  defstruct [:workspace_id, :agent_id, :invocation_id, :event]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          agent_id: String.t(),
          invocation_id: String.t(),
          event: map()
        }
end
