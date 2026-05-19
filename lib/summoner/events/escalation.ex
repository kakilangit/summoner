defmodule Summoner.Events.Escalation do
  @moduledoc "Published when an invocation failure is escalated to the user."
  @enforce_keys [:workspace_id, :invocation_id, :reason]
  defstruct [:workspace_id, :invocation_id, :reason]
  @type t :: %__MODULE__{workspace_id: String.t(), invocation_id: String.t(), reason: String.t()}
end
