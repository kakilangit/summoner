defmodule Summoner.Events do
  @moduledoc """
  Port for domain event publishing and subscription.

  Domain logic calls `publish/1` with a domain event struct.
  Application calls `subscribe/1` and `unsubscribe/1` with a
  subscription scope. The configured adapter handles routing,
  serialization, and delivery.
  """

  @adapter Application.compile_env(:summoner, :event_adapter, Summoner.Events.PubSubAdapter)

  @type scope :: Summoner.Events.Adapter.scope()

  @doc "Publish a domain event."
  @spec publish(struct()) :: :ok
  def publish(event), do: @adapter.publish(event)

  @doc "Subscribe the calling process to events for the given scope."
  @spec subscribe(scope()) :: :ok
  def subscribe(scope), do: @adapter.subscribe(scope)

  @doc "Unsubscribe from a scope."
  @spec unsubscribe(scope()) :: :ok
  def unsubscribe(scope), do: @adapter.unsubscribe(scope)
end
