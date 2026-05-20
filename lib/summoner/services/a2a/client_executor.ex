defmodule Summoner.Services.A2A.ClientExecutor do
  @moduledoc """
  Executes outbound A2A requests against remote agents.

  Builds a JSON-RPC request, resolves auth headers from the linked secret,
  and sends messages via the A2A protocol. Creates `a2a_tasks` records
  for tracking outbound interactions.

  Uses raw HTTP via `Req` instead of `A2A.Client.send_message/3` because
  the library does not handle `message/send` responses that return a
  Message instead of a Task (allowed by the A2A spec's `SendMessageResponse`
  oneof). We decode the JSON-RPC result ourselves, dispatching to
  `A2A.JSON.decode/2` with the correct type.
  """

  require Logger

  alias Summoner.Adapters.Persistence.A2A, as: SummonerA2A
  alias Summoner.Domain.Schemas.RemoteAgent
  alias Summoner.Repo
  alias Summoner.Services.A2A.ContentAdapter
  alias Summoner.Services.A2A.Discovery

  alias A2A.Message
  alias A2A.Part

  @doc """
  Sends a message to a remote agent via A2A protocol.

  Returns `{:ok, result}` where result is a map with `:content` (list of
  content blocks) and `:task` or `:message` (the decoded A2A struct),
  or `{:error, reason}`.
  """
  def send_message(agent, %RemoteAgent{} = remote, message, opts \\ []) do
    with {:ok, service_url} <- resolve_service_url(remote) do
      headers = build_auth_headers(remote)
      timeout = remote.timeout_s * 1_000

      skill = Keyword.get(opts, :skill)
      a2a_message = build_message(if(skill, do: {message, skill}, else: message))
      send_opts = Keyword.take(opts, [:task_id, :context_id, :metadata])

      with {:ok, task} <- create_outbound_task(agent, opts),
           {:ok, a2a_result} <-
             do_send_message(service_url, headers, timeout, a2a_message, send_opts) do
        update_outbound_task(task, a2a_result)
        interpret_a2a_result(a2a_result)
      else
        {:error, reason} ->
          Logger.warning("A2A outbound request to #{service_url} failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # -------------------------------------------------------------------
  # Raw JSON-RPC transport
  # -------------------------------------------------------------------

  defp do_send_message(service_url, headers, timeout, %Message{} = message, opts) do
    {:ok, encoded_msg} = A2A.JSON.encode(message)

    params =
      %{"message" => encoded_msg}
      |> put_unless_nil("taskId", Keyword.get(opts, :task_id))
      |> put_unless_nil("contextId", Keyword.get(opts, :context_id))
      |> put_unless_nil("metadata", Keyword.get(opts, :metadata))

    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "message/send",
        "params" => params,
        "id" => System.unique_integer([:positive])
      })

    req =
      Req.new(
        url: service_url,
        headers: [{"content-type", "application/json"} | headers],
        connect_options: [timeout: timeout],
        receive_timeout: timeout
      )

    case Req.post(req, body: body) do
      {:ok, %Req.Response{status: 200, body: response_body}} ->
        decode_jsonrpc_result(response_body)

      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:error, {:http_error, status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)

  defp decode_jsonrpc_result(%{"error" => error_map}) do
    {:error, {:jsonrpc_error, error_map["code"], error_map["message"]}}
  end

  # Wrapped task: {"result": {"task": {...}}}
  defp decode_jsonrpc_result(%{"result" => %{"task" => task}}) do
    A2A.JSON.decode(task, :task)
  end

  # Wrapped message: {"result": {"message": {...}}}
  defp decode_jsonrpc_result(%{"result" => %{"message" => message}}) do
    A2A.JSON.decode(message, :message)
  end

  # Bare result with "kind" discriminator
  defp decode_jsonrpc_result(%{"result" => %{"kind" => "message"} = result}) do
    A2A.JSON.decode(result, :message)
  end

  # Bare result — assume task (has "id" + "status")
  defp decode_jsonrpc_result(%{"result" => %{"id" => _, "status" => _} = result}) do
    A2A.JSON.decode(result, :task)
  end

  defp decode_jsonrpc_result(%{"result" => result}) do
    {:error, {:unexpected_result, result}}
  end

  defp decode_jsonrpc_result(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decode_jsonrpc_result(decoded)
      {:error, _} = error -> error
    end
  end

  defp decode_jsonrpc_result(body) do
    {:error, {:unexpected_body, body}}
  end

  # -------------------------------------------------------------------
  # Result interpretation
  # -------------------------------------------------------------------

  defp interpret_a2a_result(%A2A.Task{status: %{state: state}} = a2a_task)
       when state in [:failed, :rejected, :canceled] do
    error_content = extract_status_message(a2a_task) || inspect(state)
    {:error, error_content}
  end

  defp interpret_a2a_result(%A2A.Task{status: %{state: :input_required}} = a2a_task) do
    # The remote agent needs more information from the user.
    # Surface the status message as assistant content so the user can reply.
    prompt = extract_status_message(a2a_task) || "The remote agent requires additional input."
    content = [%{"type" => "text", "text" => prompt}]

    {:ok,
     %{
       content: content,
       task: a2a_task,
       input_required: true,
       task_id: a2a_task.id,
       context_id: a2a_task.context_id,
       output: %{"content" => content, "response" => prompt}
     }}
  end

  defp interpret_a2a_result(%A2A.Task{status: %{state: :auth_required}} = a2a_task) do
    prompt =
      extract_status_message(a2a_task) ||
        "The remote agent requires authentication before proceeding."

    {:error, prompt}
  end

  defp interpret_a2a_result(%A2A.Task{} = a2a_task) do
    content = extract_content(a2a_task)

    {:ok,
     %{
       content: content,
       task: a2a_task,
       output: %{"content" => content, "response" => content_to_text(content)}
     }}
  end

  defp interpret_a2a_result(%A2A.Message{} = message) do
    content = ContentAdapter.parts_to_content(message.parts || [])

    {:ok,
     %{
       content: content,
       message: message,
       output: %{"content" => content, "response" => content_to_text(content)}
     }}
  end

  # -------------------------------------------------------------------
  # Message building
  # -------------------------------------------------------------------

  defp build_message({message, %{"skill" => _} = skill_data}) when is_binary(message) do
    Message.new_user([
      Part.Text.new(message),
      Part.Data.new(skill_data)
    ])
  end

  defp build_message({message, nil}), do: build_message(message)

  defp build_message(message) when is_binary(message) do
    Message.new_user([Part.Text.new(message)])
  end

  defp build_message(%Message{} = message), do: message

  defp build_message(content_blocks) when is_list(content_blocks) do
    parts = ContentAdapter.content_to_parts(content_blocks)
    A2A.Message.new_user(parts)
  end

  # -------------------------------------------------------------------
  # Auth
  # -------------------------------------------------------------------

  defp build_auth_headers(%RemoteAgent{auth_mode: :none}), do: []

  defp build_auth_headers(%RemoteAgent{auth_mode: mode} = remote)
       when mode in [:bearer_token, :api_key] do
    case load_secret_value(remote) do
      {:ok, value} ->
        case mode do
          :bearer_token -> [{"authorization", "Bearer #{value}"}]
          :api_key -> [{"x-api-key", value}]
        end

      {:error, _} ->
        Logger.warning("Failed to load secret for remote agent auth, proceeding without auth")
        []
    end
  end

  defp build_auth_headers(_remote), do: []

  defp load_secret_value(%RemoteAgent{api_key_secret_id: nil}), do: {:error, :no_secret}

  defp load_secret_value(%RemoteAgent{api_key_secret_id: secret_id}) do
    case Repo.get(Summoner.Domain.Schemas.Secret, secret_id) do
      nil -> {:error, :secret_not_found}
      secret -> {:ok, secret.encrypted_value}
    end
  end

  # -------------------------------------------------------------------
  # Task tracking
  # -------------------------------------------------------------------

  defp create_outbound_task(agent, opts) do
    SummonerA2A.create_task(%{
      direction: :outbound,
      state: :submitted,
      agent_id: agent.id,
      context_id: Keyword.get(opts, :context_id),
      conversation_id: Keyword.get(opts, :conversation_id),
      metadata: Keyword.get(opts, :metadata, %{})
    })
  end

  defp update_outbound_task(task, %A2A.Task{status: status}) do
    state = if status, do: status.state, else: :completed
    SummonerA2A.update_task(task, %{state: state})
  end

  defp update_outbound_task(task, %A2A.Message{}) do
    SummonerA2A.update_task(task, %{state: :completed})
  end

  # -------------------------------------------------------------------
  # Content extraction
  # -------------------------------------------------------------------

  defp extract_content(%A2A.Task{artifacts: artifacts}) when is_list(artifacts) do
    artifacts
    |> Enum.flat_map(fn artifact -> artifact.parts || [] end)
    |> ContentAdapter.parts_to_content()
  end

  defp extract_content(_), do: [%{"type" => "text", "text" => ""}]

  defp extract_status_message(%A2A.Task{status: %{message: %Message{} = msg}}) do
    Message.text(msg)
  end

  defp extract_status_message(_), do: nil

  defp content_to_text(content) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("\n", & &1["text"])
  end

  # Resolves the JSON-RPC service URL by fetching/caching the agent card.
  # The card's `url` field is the actual A2A endpoint, distinct from the
  # discovery URL (agent_card_url).
  defp resolve_service_url(%RemoteAgent{} = remote) do
    case Discovery.get_or_refresh(remote) do
      {:ok, %{url: url}} when is_binary(url) and url != "" -> {:ok, url}
      {:ok, _} -> {:error, :no_service_url_in_card}
      {:error, reason} -> {:error, {:discovery_failed, reason}}
    end
  end
end
