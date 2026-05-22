defmodule Summoner.Adapters.MCP.Tools.InvokeAgent do
  @moduledoc """
  Invoke a Summoner agent with a prompt.

  Resolves the agent by ID or callname within the workspace scope,
  creates a conversation, and executes synchronously.
  """

  use Anubis.Server.Component, type: :tool

  alias Summoner.Domain.Schemas.Scope
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Conversations

  alias Anubis.MCP.Error

  schema do
    field :agent_id, :string, required: false
    field :agent_name, :string, required: false
    field :input, :string, required: true
  end

  @impl true
  def execute(args, frame) do
    workspace_id = frame.assigns[:workspace_id]
    scope = %Scope{user: nil}

    with {:ok, agent} <- resolve_agent(scope, workspace_id, args),
         {:ok, conversation_id} <- ensure_conversation(scope, workspace_id, agent),
         {:ok, invocation} <-
           Agents.execute_sync(agent, workspace_id, %{
             conversation_id: conversation_id,
             message: args.input,
             scope: scope
           }) do
      messages = Conversations.list_messages(conversation_id)

      assistant_text =
        messages
        |> Enum.filter(&(&1.role == :assistant))
        |> Enum.map_join("\n", & &1.content)

      result = %{
        invocation_id: invocation.id,
        agent_id: agent.id,
        agent_name: agent.name,
        status: to_string(invocation.status),
        response: assistant_text
      }

      {:reply, Jason.encode!(result), frame}
    else
      {:error, reason} ->
        {:error, Error.protocol(:internal_error, %{message: inspect(reason)}), frame}
    end
  end

  defp resolve_agent(scope, workspace_id, %{agent_id: agent_id})
       when is_binary(agent_id) and agent_id != "" do
    agent =
      scope
      |> Agents.get_agent!(workspace_id, agent_id)
      |> Agents.preload_agent()

    {:ok, agent}
  rescue
    Ecto.NoResultsError -> {:error, :agent_not_found}
  end

  defp resolve_agent(scope, workspace_id, %{agent_name: name})
       when is_binary(name) and name != "" do
    callname = String.replace_leading(name, "@", "")

    case Agents.get_agent_by_callname(scope, workspace_id, callname) do
      nil -> {:error, :agent_not_found}
      agent -> {:ok, Agents.preload_agent(agent)}
    end
  end

  defp resolve_agent(_scope, _workspace_id, _args) do
    {:error, :agent_id_or_name_required}
  end

  defp ensure_conversation(scope, workspace_id, agent) do
    case Conversations.create_conversation(scope, %{
           workspace_id: workspace_id,
           primary_agent_id: agent.id,
           title: "MCP Invocation"
         }) do
      {:ok, conv} -> {:ok, conv.id}
      {:error, reason} -> {:error, reason}
    end
  end
end
