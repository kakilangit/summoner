defmodule Summoner.A2A.ClientExecutor do
  @moduledoc """
  Executes outbound A2A requests against remote agents.

  Builds an `A2A.Client`, resolves auth headers from the linked secret,
  and sends messages via the A2A protocol. Creates `a2a_tasks` records
  for tracking outbound interactions.
  """

  require Logger

  alias Summoner.A2A, as: SummonerA2A
  alias Summoner.A2A.ContentAdapter
  alias Summoner.Agents.RemoteAgent
  alias Summoner.Repo

  alias A2A.Message
  alias A2A.Part

  @doc """
  Sends a message to a remote agent via A2A protocol.

  Returns `{:ok, result}` where result is a map with `:content` (list of
  content blocks) and `:task` (the A2A task), or `{:error, reason}`.
  """
  def send_message(agent, %RemoteAgent{} = remote, message, opts \\ []) do
    headers = build_auth_headers(remote)
    timeout = remote.timeout_s * 1_000

    client =
      A2A.Client.new(remote.agent_card_url,
        headers: headers,
        connect_options: [timeout: timeout]
      )

    a2a_message = build_message(message)
    send_opts = Keyword.take(opts, [:task_id, :context_id, :metadata])

    with {:ok, task} <- create_outbound_task(agent, opts),
         {:ok, a2a_task} <- A2A.Client.send_message(client, a2a_message, send_opts) do
      update_outbound_task(task, a2a_task)
      content = extract_content(a2a_task)

      {:ok,
       %{
         content: content,
         task: a2a_task,
         output: %{"content" => content, "response" => content_to_text(content)}
       }}
    else
      {:error, reason} ->
        Logger.warning(
          "A2A outbound request to #{remote.agent_card_url} failed: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp build_message(message) when is_binary(message) do
    Message.new_user([Part.Text.new(message)])
  end

  defp build_message(%Message{} = message), do: message

  defp build_message(content_blocks) when is_list(content_blocks) do
    parts = ContentAdapter.content_to_parts(content_blocks)
    A2A.Message.new_user(parts)
  end

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
    case Repo.get(Summoner.Secrets.Secret, secret_id) do
      nil -> {:error, :secret_not_found}
      secret -> {:ok, secret.encrypted_value}
    end
  end

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

  defp extract_content(%A2A.Task{artifacts: artifacts}) when is_list(artifacts) do
    artifacts
    |> Enum.flat_map(fn artifact -> artifact.parts || [] end)
    |> ContentAdapter.parts_to_content()
  end

  defp extract_content(_), do: [%{"type" => "text", "text" => ""}]

  defp content_to_text(content) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("\n", & &1["text"])
  end
end
