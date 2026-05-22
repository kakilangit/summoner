defmodule Summoner.Services.EventRules.SendNotificationDispatcher do
  @moduledoc """
  Action dispatcher that sends a notification when an event rule fires.

  Currently logs the notification. Will integrate with plugin bonds and
  notification channels when available.
  """

  @behaviour Summoner.Services.EventRules.ActionDispatcher

  require Logger

  @impl true
  def dispatch(action_config, event_data) do
    channel = action_config["channel"] || "log"
    template = action_config["template"]

    message =
      if template, do: interpolate(template, event_data), else: default_message(event_data)

    case channel do
      "log" ->
        Logger.info("Event rule notification: #{message}")
        {:ok, %{channel: "log", message: message}}

      _other ->
        Logger.info("Event rule notification (#{channel}): #{message}")
        {:ok, %{channel: channel, message: message}}
    end
  end

  defp interpolate(template, event_data) do
    Summoner.Services.EventRules.InvokeAgentDispatcher.interpolate(template, event_data)
  end

  defp default_message(event_data) do
    event_type = event_data["event_type"] || "unknown"
    "Event rule fired for #{event_type}"
  end
end
