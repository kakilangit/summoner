defmodule Summoner.Domain.Events.MediaGenerationFailed do
  @moduledoc "Published when media generation fails."
  @enforce_keys [:workspace_id, :conversation_id, :attachment_id, :error]
  defstruct [:workspace_id, :conversation_id, :attachment_id, :error]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          conversation_id: String.t(),
          attachment_id: String.t(),
          error: String.t()
        }
end
