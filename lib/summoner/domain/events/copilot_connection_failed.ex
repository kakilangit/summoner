defmodule Summoner.Domain.Events.CopilotConnectionFailed do
  @moduledoc "Published when a Copilot provider connection fails."
  @enforce_keys [:workspace_id, :provider_id, :reason]
  defstruct [:workspace_id, :provider_id, :reason]
  @type t :: %__MODULE__{workspace_id: String.t(), provider_id: String.t(), reason: term()}
end
