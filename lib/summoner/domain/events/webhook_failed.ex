defmodule Summoner.Domain.Events.WebhookFailed do
  @moduledoc "Published when a webhook trigger fails."
  @enforce_keys [:webhook_id, :workspace_id, :error_reason]
  defstruct [:webhook_id, :workspace_id, :error_reason, :timestamp]

  @type t :: %__MODULE__{
          webhook_id: String.t(),
          workspace_id: String.t(),
          error_reason: atom() | String.t(),
          timestamp: DateTime.t() | nil
        }
end
