defmodule Summoner.Domain.Events.CopilotConnected do
  @moduledoc "Published when a Copilot provider connects successfully."
  @enforce_keys [:workspace_id, :provider_id]
  defstruct [:workspace_id, :provider_id]
  @type t :: %__MODULE__{workspace_id: String.t(), provider_id: String.t()}
end
