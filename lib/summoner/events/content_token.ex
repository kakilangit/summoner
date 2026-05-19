defmodule Summoner.Events.ContentToken do
  @moduledoc "Published when a streaming token is emitted during inference."
  @enforce_keys [:workspace_id, :agent_id, :invocation_id, :token]
  defstruct [:workspace_id, :agent_id, :invocation_id, :token]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          agent_id: String.t(),
          invocation_id: String.t(),
          token: String.t()
        }
end
