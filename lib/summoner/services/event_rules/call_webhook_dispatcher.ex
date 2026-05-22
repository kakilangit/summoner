defmodule Summoner.Services.EventRules.CallWebhookDispatcher do
  @moduledoc """
  Action dispatcher that calls an external webhook URL when an event rule fires.

  Sends a POST request with the event data as JSON body. Supports configurable
  HTTP method, headers, and body template.
  """

  @behaviour Summoner.Services.EventRules.ActionDispatcher

  alias Summoner.Services.EventRules.InvokeAgentDispatcher

  require Logger

  @default_timeout_ms 15_000

  @impl true
  def dispatch(action_config, event_data) do
    url = action_config["url"]
    method = parse_method(action_config["method"])
    headers = parse_headers(action_config["headers"])
    body = build_body(action_config, event_data)
    timeout = action_config["timeout_ms"] || @default_timeout_ms

    case Req.request(
           method: method,
           url: url,
           json: body,
           headers: headers,
           receive_timeout: timeout
         ) do
      {:ok, %Req.Response{status: status} = resp} when status in 200..299 ->
        {:ok, %{status: status, body: resp.body}}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, "HTTP #{status}: #{inspect(resp_body)}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp parse_method(nil), do: :post
  defp parse_method("GET"), do: :get
  defp parse_method("PUT"), do: :put
  defp parse_method("PATCH"), do: :patch
  defp parse_method("DELETE"), do: :delete
  defp parse_method(_), do: :post

  defp parse_headers(nil), do: []
  defp parse_headers(%{} = headers), do: Enum.map(headers, fn {k, v} -> {k, v} end)
  defp parse_headers(_), do: []

  defp build_body(%{"body_template" => template}, event_data) when is_map(template) do
    interpolate_map(template, event_data)
  end

  defp build_body(_config, event_data), do: event_data

  defp interpolate_map(template, data) when is_map(template) do
    Map.new(template, fn {k, v} -> {k, interpolate_value(v, data)} end)
  end

  defp interpolate_value(v, data) when is_binary(v) do
    InvokeAgentDispatcher.interpolate(v, data)
  end

  defp interpolate_value(v, data) when is_map(v), do: interpolate_map(v, data)
  defp interpolate_value(v, _data), do: v
end
