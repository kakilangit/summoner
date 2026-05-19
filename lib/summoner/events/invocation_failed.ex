defmodule Summoner.Events.InvocationFailed do
  @moduledoc "Published when an invocation fails."
  @enforce_keys [:workspace_id, :agent_id, :invocation_id]
  defstruct [:workspace_id, :agent_id, :invocation_id, :output]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          agent_id: String.t(),
          invocation_id: String.t(),
          output: map() | nil
        }
end
