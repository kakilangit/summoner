defmodule Summoner.Domain.Events.Failover do
  @moduledoc """
  Domain event emitted when an agent fails over to its backup.
  """

  @enforce_keys [:invocation_id, :from_agent_id, :to_agent_id, :reason, :depth]
  defstruct [:invocation_id, :from_agent_id, :to_agent_id, :reason, :depth, :workspace_id]
end
