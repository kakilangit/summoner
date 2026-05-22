defmodule Summoner.Adapters.MCP.Tools.ListPipelines do
  @moduledoc "List available pipelines in the workspace."

  use Anubis.Server.Component, type: :tool

  alias Summoner.Domain.Schemas.Scope
  alias Summoner.Ports.Persistence.Pipelines

  schema do
    field :status, :string, required: false
  end

  @impl true
  def execute(_args, frame) do
    workspace_id = frame.assigns[:workspace_id]
    scope = %Scope{user: nil}

    pipelines = Pipelines.list_pipelines(scope, workspace_id)

    items =
      Enum.map(pipelines, fn p ->
        %{
          id: p.id,
          name: p.name,
          description: p.description,
          mode: to_string(p.mode),
          stage_count: length(p.stages || [])
        }
      end)

    {:reply, Jason.encode!(%{pipelines: items, count: length(items)}), frame}
  end
end
