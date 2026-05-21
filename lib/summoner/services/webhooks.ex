defmodule Summoner.Services.Webhooks do
  @moduledoc """
  Orchestration service for webhook (Beacon) triggers.

  Handles auth verification, input transformation, rate limiting,
  and routing to the appropriate target (agent, pipeline, or swarm).
  """

  alias Summoner.Domain.Policies.InputTransform
  alias Summoner.Domain.Policies.WebhookAuth
  alias Summoner.Domain.Policies.WebhookRateLimit
  alias Summoner.Ports.Persistence.AccessTokens
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Conversations
  alias Summoner.Ports.Persistence.Secrets
  alias Summoner.Ports.Persistence.Webhooks

  @type trigger_result ::
          {:ok, :async, map()}
          | {:ok, :sync, map()}
          | {:error, :not_found | :disabled | :unauthorized | :rate_limited | term()}

  @doc """
  Triggers a webhook. Performs auth, rate limiting, transformation,
  and routes to the target.

  ## Options

    * `:auth_header` — `Authorization` header value
    * `:signature` — `X-Signature-256` header value
    * `:raw_body` — raw request body (for HMAC verification)

  """
  @spec trigger(String.t(), map(), keyword()) :: trigger_result()
  def trigger(webhook_id, body_params, opts \\ []) do
    with {:ok, webhook} <- fetch_webhook(webhook_id),
         :ok <- check_enabled(webhook),
         :ok <- verify_auth(webhook, opts),
         :ok <- check_rate_limit(webhook) do
      Webhooks.increment_trigger_count(webhook_id)
      input = InputTransform.apply_transform(body_params, webhook.transform)
      route_to_target(webhook, input)
    end
  end

  defp fetch_webhook(id) do
    case Webhooks.get_webhook(id) do
      nil -> {:error, :not_found}
      webhook -> {:ok, webhook}
    end
  end

  defp check_enabled(%{enabled: true}), do: :ok
  defp check_enabled(%{enabled: false}), do: {:error, :disabled}

  defp verify_auth(%{auth_mode: :public} = webhook, _opts) do
    WebhookAuth.verify(webhook, [])
  end

  defp verify_auth(%{auth_mode: :token} = webhook, opts) do
    token_string = extract_bearer_token(Keyword.get(opts, :auth_header))

    token_valid =
      case token_string do
        nil -> false
        t -> match?({:ok, _}, AccessTokens.verify_token(t, scope: "webhook"))
      end

    WebhookAuth.verify(webhook, token_valid: token_valid)
  end

  defp verify_auth(%{auth_mode: :hmac} = webhook, opts) do
    secret_value = resolve_hmac_secret(webhook)

    WebhookAuth.verify(webhook,
      signature: Keyword.get(opts, :signature),
      raw_body: Keyword.get(opts, :raw_body),
      secret_value: secret_value
    )
  end

  defp extract_bearer_token(nil), do: nil
  defp extract_bearer_token("Bearer " <> token), do: token
  defp extract_bearer_token(_), do: nil

  defp resolve_hmac_secret(%{hmac_secret_id: nil}), do: nil

  defp resolve_hmac_secret(%{hmac_secret_id: id}) do
    case Secrets.get_secret_by_id(id) do
      nil -> nil
      secret -> secret.encrypted_value
    end
  end

  defp check_rate_limit(%{rate_limit_rpm: nil}), do: :ok

  defp check_rate_limit(webhook) do
    # Simple check: compare trigger_count against RPM
    # For Phase 1, we use a simple count-based approach.
    # A more sophisticated sliding window can be added later.
    WebhookRateLimit.check(webhook, [])
  end

  defp route_to_target(%{target_type: :agent} = webhook, input) do
    scope = %{user: nil}
    agent = Agents.get_agent!(scope, webhook.workspace_id, webhook.target_id)
    agent = Agents.preload_agent(agent)
    message = Map.get(input, "message", Jason.encode!(input))

    {:ok, conversation} =
      Conversations.create_conversation(scope, %{
        workspace_id: webhook.workspace_id,
        primary_agent_id: agent.id,
        title: "Webhook: #{webhook.name}"
      })

    invoke_params = %{
      conversation_id: conversation.id,
      message: message,
      scope: scope
    }

    case webhook.response_mode do
      :async ->
        Agents.execute_async(agent, webhook.workspace_id, invoke_params)
        {:ok, :async, %{conversation_id: conversation.id, status: "accepted"}}

      :sync ->
        case Agents.execute_sync(agent, webhook.workspace_id, invoke_params) do
          {:ok, invocation} ->
            messages = Conversations.list_messages(conversation.id)

            {:ok, :sync,
             %{
               invocation_id: invocation.id,
               conversation_id: conversation.id,
               status: to_string(invocation.status),
               messages: Enum.map(messages, &message_data/1)
             }}

          {:error, reason} ->
            {:error, reason}
        end

      :stream ->
        # Stream mode returns the conversation_id for the caller to subscribe
        Agents.execute_async(agent, webhook.workspace_id, invoke_params)

        {:ok, :stream,
         %{
           conversation_id: conversation.id,
           agent_id: agent.id,
           workspace_id: webhook.workspace_id
         }}
    end
  end

  defp route_to_target(%{target_type: target_type}, _input)
       when target_type in [:pipeline, :swarm] do
    # Pipeline and swarm routing will be added in Phase 2
    {:error, {:not_implemented, target_type}}
  end

  defp message_data(msg) do
    %{
      id: msg.id,
      role: msg.role,
      content: msg.content,
      inserted_at: msg.inserted_at
    }
  end
end
