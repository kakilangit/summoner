defmodule Summoner.Events.MediaGenerationStarted do
  @moduledoc "Published when media generation begins for an attachment."
  @enforce_keys [:workspace_id, :conversation_id, :attachment_id, :type, :prompt]
  defstruct [:workspace_id, :conversation_id, :attachment_id, :type, :prompt]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          conversation_id: String.t(),
          attachment_id: String.t(),
          type: String.t(),
          prompt: String.t()
        }
end
