defmodule Summoner.Events.Adapter do
  @moduledoc """
  Behaviour for event publishing adapters.

  Adapters convert domain event structs to infrastructure-specific
  formats and handle routing (e.g., PubSub topics).
  """

  @type scope ::
          {:agent, workspace_id :: String.t(), agent_id :: String.t()}
          | {:invocation, workspace_id :: String.t(), invocation_id :: String.t()}
          | {:invocation_events, workspace_id :: String.t(), invocation_id :: String.t()}
          | {:escalations, workspace_id :: String.t()}
          | {:conversation, workspace_id :: String.t(), conversation_id :: String.t()}
          | {:pipeline, workspace_id :: String.t(), pipeline_id :: String.t()}
          | {:provider, workspace_id :: String.t(), provider_id :: String.t()}
          | {:swarm, workspace_id :: String.t(), swarm_id :: String.t()}
          | {:agent_config, agent_id :: String.t()}

  @callback publish(event :: struct()) :: :ok
  @callback subscribe(scope()) :: :ok
  @callback unsubscribe(scope()) :: :ok
end
