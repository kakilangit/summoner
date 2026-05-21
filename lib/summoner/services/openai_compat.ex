defmodule Summoner.Services.OpenAICompat do
  @moduledoc """
  Orchestration service for OpenAI-compatible API.

  Resolves model names to agents, creates ephemeral conversations,
  and delegates to the agent execution system.
  """

  alias Summoner.Domain.Policies.OpenAICompat, as: Formatter
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Conversations

  @doc """
  Handles a non-streaming chat completion request.

  Resolves the model to an agent, creates an ephemeral conversation,
  invokes the agent synchronously, and formats the response.
  """
  @spec complete(String.t(), list(map()), map(), map()) ::
          {:ok, map()} | {:error, atom(), String.t()}
  def complete(model, messages, _params, %{workspace_id: workspace_id, scope: scope}) do
    with {:ok, input} <- Formatter.extract_input(messages),
         {:ok, agent} <- resolve_agent(model, scope, workspace_id),
         {:ok, conversation_id} <- ensure_conversation(scope, workspace_id, agent),
         {:ok, invocation} <- invoke_agent(agent, workspace_id, conversation_id, input, scope) do
      {:ok, Formatter.format_completion(invocation, model)}
    end
  end

  @doc """
  Resolves a model string to an agent.
  """
  @spec resolve_agent(String.t(), map(), String.t()) ::
          {:ok, struct()} | {:error, :not_found, String.t()}
  def resolve_agent(model, scope, workspace_id) do
    case Formatter.parse_model(model) do
      {:agent, callname} ->
        case Agents.get_agent_by_callname(scope, workspace_id, callname) do
          nil -> {:error, :not_found, "Model '#{model}' not found"}
          agent -> {:ok, agent}
        end

      {:raw, _provider, _model} ->
        # Phase 3: direct model access
        {:error, :not_implemented, "Raw model access not yet supported"}

      {:error, :invalid_model} ->
        {:error, :invalid_model, "Invalid model format. Use 'summoner:<callname>'"}
    end
  end

  # -- Private ---------------------------------------------------------------

  defp ensure_conversation(scope, workspace_id, agent) do
    case Conversations.create_conversation(scope, %{
           workspace_id: workspace_id,
           primary_agent_id: agent.id,
           title: "OpenAI API"
         }) do
      {:ok, conv} -> {:ok, conv.id}
      {:error, _} -> {:error, :internal, "Failed to create conversation"}
    end
  end

  defp invoke_agent(agent, workspace_id, conversation_id, message, scope) do
    params = %{conversation_id: conversation_id, message: message, scope: scope}

    case Agents.execute_sync(agent, workspace_id, params) do
      {:ok, invocation} ->
        {:ok, invocation}

      {:error, reason} ->
        {:error, :invocation_failed, "Invocation failed: #{inspect(reason)}"}
    end
  end
end
