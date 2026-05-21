defmodule Summoner.Domain.Events.WebhookTriggered do
  @moduledoc "Published when a webhook is successfully triggered."
  @enforce_keys [:webhook_id, :workspace_id, :response_mode, :invocation_id]
  defstruct [:webhook_id, :workspace_id, :response_mode, :invocation_id, :timestamp]

  @type t :: %__MODULE__{
          webhook_id: String.t(),
          workspace_id: String.t(),
          response_mode: atom(),
          invocation_id: String.t(),
          timestamp: DateTime.t() | nil
        }
end
