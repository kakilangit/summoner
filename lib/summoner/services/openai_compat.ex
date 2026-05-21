defmodule Summoner.Services.OpenAICompat do
  @moduledoc """
  Orchestration service for OpenAI-compatible API.

  Resolves model names to agents or raw providers, creates ephemeral
  conversations, and delegates to the agent execution or inference system.
  """

  alias Arcanum.Intent
  alias Arcanum.Response
  alias Summoner.Domain.Policies.OpenAICompat, as: Formatter
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Conversations
  alias Summoner.Ports.Persistence.Providers
  alias Summoner.Services.Inference.Gateway

  @doc """
  Handles a non-streaming chat completion request.

  Resolves the model to an agent or raw provider, invokes, and formats.
  """
  @spec complete(String.t(), list(map()), map(), map()) ::
          {:ok, map()} | {:error, atom(), String.t()}
  def complete(model, messages, params, %{workspace_id: workspace_id, scope: scope} = context) do
    tenant_id = Map.get(context, :tenant_id)

    case Formatter.parse_model(model) do
      {:agent, _callname} ->
        with {:ok, input} <- Formatter.extract_input(messages),
             {:ok, agent} <- resolve_agent(model, scope, workspace_id),
             {:ok, conversation_id} <- ensure_conversation(scope, workspace_id, agent),
             {:ok, invocation} <- invoke_agent(agent, workspace_id, conversation_id, input, scope) do
          {:ok, Formatter.format_completion(invocation, model)}
        end

      {:raw, provider_name, model_name} ->
        complete_raw(
          model,
          provider_name,
          model_name,
          messages,
          params,
          scope,
          workspace_id,
          tenant_id
        )

      {:error, :invalid_model} ->
        {:error, :invalid_model,
         "Invalid model format. Use 'summoner:<callname>' or 'summoner:raw:<provider>/<model>'"}
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
        {:error, :invalid_model, "Use resolve_agent only for agent models"}

      {:error, :invalid_model} ->
        {:error, :invalid_model, "Invalid model format. Use 'summoner:<callname>'"}
    end
  end

  @doc """
  Resolves a raw model string to a provider struct.

  Returns `{:ok, provider, model_name}` or `{:error, ...}`.
  """
  @spec resolve_raw_provider(String.t(), String.t(), map(), String.t(), String.t() | nil) ::
          {:ok, struct(), String.t()} | {:error, atom(), String.t()}
  def resolve_raw_provider(provider_name, model_name, scope, workspace_id, tenant_id) do
    providers = Providers.list_providers(scope, workspace_id, tenant_id)

    case Enum.find(providers, &(String.downcase(&1.name) == String.downcase(provider_name))) do
      nil ->
        {:error, :not_found, "Provider '#{provider_name}' not found"}

      provider ->
        {:ok, provider, model_name}
    end
  end

  # -- Private ---------------------------------------------------------------

  defp complete_raw(
         model,
         provider_name,
         model_name,
         messages,
         params,
         scope,
         workspace_id,
         tenant_id
       ) do
    with {:ok, provider, resolved_model} <-
           resolve_raw_provider(provider_name, model_name, scope, workspace_id, tenant_id) do
      openai_messages = convert_messages(messages)

      intent = %Intent{
        model: resolved_model,
        messages: openai_messages,
        temperature: params["temperature"],
        max_tokens: params["max_tokens"]
      }

      case Gateway.chat(provider, intent) do
        {:ok, %Response{} = response} ->
          {:ok, format_raw_response(response, model)}

        {:error, reason} ->
          {:error, :invocation_failed, "Inference failed: #{inspect(reason)}"}
      end
    end
  end

  defp convert_messages(messages) when is_list(messages) do
    Enum.map(messages, fn msg ->
      %{role: msg["role"] || "user", content: Intent.text(msg["content"] || "")}
    end)
  end

  defp format_raw_response(%Response{} = response, model) do
    content = Response.text(response) || ""
    usage = response.usage || %{}

    %{
      "id" => "chatcmpl-#{Ecto.UUID.generate()}",
      "object" => "chat.completion",
      "created" => System.system_time(:second),
      "model" => model,
      "choices" => [
        %{
          "index" => 0,
          "message" => %{"role" => "assistant", "content" => content},
          "finish_reason" => response.finish_reason || "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => Map.get(usage, :input_tokens, 0),
        "completion_tokens" => Map.get(usage, :output_tokens, 0),
        "total_tokens" => Map.get(usage, :total_tokens, 0)
      }
    }
  end

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
