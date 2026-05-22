defmodule Summoner.Adapters.MCP.Tools.ListAgents do
  @moduledoc "List all available agents in the workspace."

  use Anubis.Server.Component, type: :tool

  alias Summoner.Domain.Schemas.Scope
  alias Summoner.Ports.Persistence.Agents

  schema do
    field :status, :string, required: false
    field :type, :string, required: false
  end

  @impl true
  def execute(args, frame) do
    workspace_id = frame.assigns[:workspace_id]
    scope = %Scope{user: nil}

    agents = Agents.list_agents(scope, workspace_id)

    agents =
      agents
      |> maybe_filter_type(args[:type])
      |> maybe_filter_status(args[:status])

    items =
      Enum.map(agents, fn agent ->
        %{
          id: agent.id,
          name: agent.name,
          callname: agent.callname,
          type: to_string(agent.type),
          status: to_string(agent.status),
          description: agent.description
        }
      end)

    {:reply, Jason.encode!(%{agents: items, count: length(items)}), frame}
  end

  defp maybe_filter_type(agents, nil), do: agents
  defp maybe_filter_type(agents, ""), do: agents

  defp maybe_filter_type(agents, type) do
    type_atom = String.to_existing_atom(type)
    Enum.filter(agents, &(&1.type == type_atom))
  rescue
    ArgumentError -> agents
  end

  defp maybe_filter_status(agents, nil), do: agents
  defp maybe_filter_status(agents, ""), do: agents
  defp maybe_filter_status(agents, "all"), do: agents

  defp maybe_filter_status(agents, status) do
    status_atom = String.to_existing_atom(status)
    Enum.filter(agents, &(&1.status == status_atom))
  rescue
    ArgumentError -> agents
  end
end
