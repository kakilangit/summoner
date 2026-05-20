defmodule Summoner.Domain.Events.PipelineRunStatus do
  @moduledoc "Published when a pipeline run status changes."
  @enforce_keys [:workspace_id, :pipeline_id, :run_id, :status]
  defstruct [:workspace_id, :pipeline_id, :run_id, :status]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          pipeline_id: String.t(),
          run_id: String.t(),
          status: atom()
        }
end
