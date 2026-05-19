defmodule Summoner.Events.PipelineStageInvocation do
  @moduledoc "Published when a pipeline stage starts an invocation."
  @enforce_keys [:workspace_id, :pipeline_id, :run_id, :position, :invocation_id]
  defstruct [:workspace_id, :pipeline_id, :run_id, :position, :invocation_id]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          pipeline_id: String.t(),
          run_id: String.t(),
          position: integer(),
          invocation_id: String.t()
        }
end
