defmodule Summoner.Services.EventRules.ActionDispatcher do
  @moduledoc """
  Behaviour for event rule action dispatchers.

  Each action type (invoke_agent, run_pipeline, call_webhook, send_notification)
  has a dispatcher that knows how to execute the action with the given config
  and triggering event data.
  """

  @type action_config :: map()
  @type event_data :: map()
  @type result :: {:ok, map()} | {:error, term()}

  @callback dispatch(action_config(), event_data()) :: result()
end
