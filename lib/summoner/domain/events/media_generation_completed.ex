defmodule Summoner.Domain.Events.MediaGenerationCompleted do
  @moduledoc "Published when media generation completes successfully."
  @enforce_keys [:workspace_id, :conversation_id, :attachment_id, :url]
  defstruct [:workspace_id, :conversation_id, :attachment_id, :url]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          conversation_id: String.t(),
          attachment_id: String.t(),
          url: String.t()
        }
end
