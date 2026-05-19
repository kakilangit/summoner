defmodule Summoner.Events.PipelineStageStatus do
  @moduledoc "Published when a pipeline stage status changes."
  @enforce_keys [:workspace_id, :pipeline_id, :run_id, :position, :status]
  defstruct [:workspace_id, :pipeline_id, :run_id, :position, :status]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          pipeline_id: String.t(),
          run_id: String.t(),
          position: integer(),
          status: atom()
        }
end
