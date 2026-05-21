defmodule Summoner.Domain.Policies.OpenAICompat do
  @moduledoc """
  Pure formatting functions for OpenAI-compatible API.

  Converts between OpenAI chat completion format and Summoner's
  internal content/invocation format. No side effects.
  """

  @doc """
  Extracts the user message from OpenAI-format messages list.

  Takes the last user message as the input. System messages are ignored
  (the agent has its own system prompt). Prior messages become conversation
  context but for now we only support single-turn.
  """
  @spec extract_input(list(map())) :: {:ok, String.t()} | {:error, :no_user_message}
  def extract_input(messages) when is_list(messages) do
    case Enum.reverse(messages) |> Enum.find(&(&1["role"] == "user")) do
      %{"content" => content} when is_binary(content) -> {:ok, content}
      _ -> {:error, :no_user_message}
    end
  end

  def extract_input(_), do: {:error, :no_user_message}

  @doc """
  Parses a model string into a resolution type.

  - `"summoner:<callname>"` → `{:agent, callname}`
  - `"summoner:raw:<provider>/<model>"` → `{:raw, provider_name, model_name}`
  - anything else → `{:error, :invalid_model}`
  """
  @spec parse_model(String.t()) ::
          {:agent, String.t()} | {:raw, String.t(), String.t()} | {:error, :invalid_model}
  def parse_model("summoner:" <> rest) do
    case rest do
      "raw:" <> provider_model ->
        case String.split(provider_model, "/", parts: 2) do
          [provider, model] when provider != "" and model != "" ->
            {:raw, provider, model}

          _ ->
            {:error, :invalid_model}
        end

      callname when callname != "" ->
        {:agent, callname}

      _ ->
        {:error, :invalid_model}
    end
  end

  def parse_model(_), do: {:error, :invalid_model}

  @doc """
  Formats a completed invocation as an OpenAI chat completion response.
  """
  @spec format_completion(map(), String.t()) :: map()
  def format_completion(invocation, model) do
    content = extract_output(invocation)

    %{
      "id" => "chatcmpl-#{invocation.id}",
      "object" => "chat.completion",
      "created" => System.system_time(:second),
      "model" => model,
      "choices" => [
        %{
          "index" => 0,
          "message" => %{"role" => "assistant", "content" => content},
          "finish_reason" => map_finish_reason(invocation.end_reason)
        }
      ],
      "usage" => %{
        "prompt_tokens" => 0,
        "completion_tokens" => 0,
        "total_tokens" => 0
      }
    }
  end

  @doc """
  Formats an error as an OpenAI-compatible error response.
  """
  @spec format_error(String.t(), String.t(), integer()) :: map()
  def format_error(message, type \\ "invalid_request_error", code \\ nil) do
    error = %{"message" => message, "type" => type}
    error = if code, do: Map.put(error, "code", code), else: error
    %{"error" => error}
  end

  @doc """
  Formats a single SSE chunk for streaming.
  """
  @spec format_chunk(String.t(), String.t(), String.t() | nil) :: map()
  def format_chunk(invocation_id, model, content) do
    delta =
      if content, do: %{"content" => content}, else: %{}

    %{
      "id" => "chatcmpl-#{invocation_id}",
      "object" => "chat.completion.chunk",
      "created" => System.system_time(:second),
      "model" => model,
      "choices" => [
        %{
          "index" => 0,
          "delta" => delta,
          "finish_reason" => if(is_nil(content), do: "stop", else: nil)
        }
      ]
    }
  end

  # -- Private ---------------------------------------------------------------

  defp extract_output(%{output: %{"response" => response}}), do: response
  defp extract_output(%{output: %{"error" => error}}), do: "Error: #{error}"
  defp extract_output(%{output: nil}), do: ""
  defp extract_output(_), do: ""

  defp map_finish_reason(:completed), do: "stop"
  defp map_finish_reason(:token_limit_reached), do: "length"
  defp map_finish_reason(:step_limit_reached), do: "stop"
  defp map_finish_reason(:cancelled), do: "stop"
  defp map_finish_reason(_), do: "stop"
end
