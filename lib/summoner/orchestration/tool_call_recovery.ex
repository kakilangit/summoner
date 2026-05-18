defmodule Summoner.Orchestration.ToolCallRecovery do
  @moduledoc """
  Recovers swarm signal tool calls that lost their name during streaming.

  Some providers (notably Copilot/OpenAI-compatible endpoints) stream multi-tool
  responses where the tool name arrives only in the first delta for an index.
  If that delta is lost or arrives with `name: nil`, the merged tool call ends up
  with valid arguments but no name — and gets filtered as malformed by the
  normalizer.

  This module inspects nameless tool calls and infers the name from known
  argument shapes (swarm signals: `__relay__`, `__done__`).
  """

  require Logger

  alias Arcanum.Response

  @relay_tool_name "__relay__"
  @done_tool_name "__done__"

  @doc """
  Recovers nameless tool calls by inferring the name from argument structure.

  Returns the response with any recoverable tool calls patched with their
  inferred name and a synthetic id.
  """
  @spec recover(Response.t()) :: Response.t()
  def recover(%Response{tool_calls: nil} = response), do: response
  def recover(%Response{tool_calls: []} = response), do: response

  def recover(%Response{tool_calls: tool_calls} = response) do
    recovered = Enum.map(tool_calls, &maybe_recover/1)
    %{response | tool_calls: recovered}
  end

  defp maybe_recover(%{function: %{name: name}} = tc)
       when is_binary(name) and name != "" do
    tc
  end

  defp maybe_recover(%{function: %{arguments: args}} = tc)
       when is_binary(args) and args != "" do
    case Jason.decode(args) do
      {:ok, parsed} when is_map(parsed) ->
        case infer_signal_name(parsed) do
          nil ->
            tc

          name ->
            Logger.info("Recovered nameless tool call as #{name} from args: #{args}")

            tc
            |> put_in([:function, :name], name)
            |> ensure_id()
        end

      _ ->
        tc
    end
  end

  defp maybe_recover(tc), do: tc

  defp infer_signal_name(%{"next_agent" => _}), do: @relay_tool_name
  defp infer_signal_name(%{"summary" => _}), do: @done_tool_name
  defp infer_signal_name(_), do: nil

  defp ensure_id(%{id: nil} = tc),
    do: %{tc | id: "recovered_#{:erlang.unique_integer([:positive])}"}

  defp ensure_id(%{id: id} = tc) when is_binary(id) and id != "", do: tc
  defp ensure_id(tc), do: %{tc | id: "recovered_#{:erlang.unique_integer([:positive])}"}
end
