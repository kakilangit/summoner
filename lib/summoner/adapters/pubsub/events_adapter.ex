defmodule Summoner.Adapters.PubSub.EventsAdapter do
  @moduledoc """
  PubSub implementation of the event adapter.

  Converts domain event structs to PubSub broadcasts, routing each
  event to the appropriate topic(s). Subscribers receive the domain
  event struct directly in `handle_info/2`.
  """

  @behaviour Summoner.Ports.Events.Adapter

  alias Summoner.Domain.Events.{
    AgentConfigChanged,
    ContentToken,
    CopilotConnected,
    CopilotConnectionFailed,
    Escalation,
    Failover,
    InvocationCompleted,
    InvocationEvent,
    InvocationFailed,
    InvocationStarted,
    MediaGenerationCompleted,
    MediaGenerationFailed,
    MediaGenerationStarted,
    PipelineRunStatus,
    PipelineStageInvocation,
    PipelineStageStatus,
    SwarmDone,
    SwarmTimeout,
    SwarmTurn
  }

  @pubsub Summoner.PubSub

  # -------------------------------------------------------------------
  # Publish
  # -------------------------------------------------------------------

  @impl true
  def publish(event) do
    for topic <- topics(event) do
      Phoenix.PubSub.broadcast(@pubsub, topic, event)
    end

    # Always broadcast to global topic for event rule evaluation
    Phoenix.PubSub.broadcast(@pubsub, "events:global", event)

    :ok
  end

  # -------------------------------------------------------------------
  # Subscribe / Unsubscribe
  # -------------------------------------------------------------------

  @impl true
  def subscribe(scope) do
    Phoenix.PubSub.subscribe(@pubsub, topic_for_scope(scope))
    :ok
  end

  @impl true
  def unsubscribe(scope) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic_for_scope(scope))
    :ok
  end

  # -------------------------------------------------------------------
  # Topic routing — event → topic(s)
  # -------------------------------------------------------------------

  defp topics(%InvocationStarted{} = e), do: [agent_topic(e), invocation_topic(e)]
  defp topics(%InvocationCompleted{} = e), do: [agent_topic(e), invocation_topic(e)]
  defp topics(%InvocationFailed{} = e), do: [agent_topic(e), invocation_topic(e)]
  defp topics(%InvocationEvent{} = e), do: [invocation_events_topic(e)]
  defp topics(%ContentToken{} = e), do: [agent_topic(e)]
  defp topics(%Escalation{} = e), do: [escalations_topic(e)]
  defp topics(%SwarmTurn{} = e), do: [swarm_topic(e)]
  defp topics(%SwarmDone{} = e), do: [swarm_topic(e)]
  defp topics(%SwarmTimeout{} = e), do: [swarm_topic(e)]
  defp topics(%MediaGenerationStarted{} = e), do: [conversation_topic(e)]
  defp topics(%MediaGenerationCompleted{} = e), do: [conversation_topic(e)]
  defp topics(%MediaGenerationFailed{} = e), do: [conversation_topic(e)]
  defp topics(%PipelineRunStatus{} = e), do: [pipeline_topic(e)]
  defp topics(%PipelineStageStatus{} = e), do: [pipeline_topic(e)]
  defp topics(%PipelineStageInvocation{} = e), do: [pipeline_topic(e)]
  defp topics(%CopilotConnected{} = e), do: [provider_topic(e)]
  defp topics(%CopilotConnectionFailed{} = e), do: [provider_topic(e)]
  defp topics(%AgentConfigChanged{} = e), do: [agent_config_topic(e)]
  defp topics(%Failover{} = e), do: [failover_topic(e)]

  # -------------------------------------------------------------------
  # Topic builders
  # -------------------------------------------------------------------

  defp agent_topic(%{workspace_id: w, agent_id: a}), do: "agent:#{w}:#{a}"
  defp invocation_topic(%{workspace_id: w, invocation_id: i}), do: "invocation:#{w}:#{i}"

  defp invocation_events_topic(%{workspace_id: w, invocation_id: i}),
    do: "invocation_events:#{w}:#{i}"

  defp escalations_topic(%{workspace_id: w}), do: "escalations:#{w}"
  defp conversation_topic(%{workspace_id: w, conversation_id: c}), do: "conversation:#{w}:#{c}"
  defp pipeline_topic(%{workspace_id: w, pipeline_id: p}), do: "pipeline:#{w}:#{p}"
  defp provider_topic(%{workspace_id: w, provider_id: p}), do: "provider:#{w}:#{p}"
  defp swarm_topic(%{workspace_id: w, swarm_id: s}), do: "swarm:#{w}:#{s}"
  defp agent_config_topic(%{agent_id: a}), do: "agent_config:#{a}"
  defp failover_topic(%{workspace_id: w}), do: "failover:#{w}"

  # -------------------------------------------------------------------
  # Scope → topic string
  # -------------------------------------------------------------------

  defp topic_for_scope({:agent, w, a}), do: "agent:#{w}:#{a}"
  defp topic_for_scope({:invocation, w, i}), do: "invocation:#{w}:#{i}"
  defp topic_for_scope({:invocation_events, w, i}), do: "invocation_events:#{w}:#{i}"
  defp topic_for_scope({:escalations, w}), do: "escalations:#{w}"
  defp topic_for_scope({:conversation, w, c}), do: "conversation:#{w}:#{c}"
  defp topic_for_scope({:pipeline, w, p}), do: "pipeline:#{w}:#{p}"
  defp topic_for_scope({:provider, w, p}), do: "provider:#{w}:#{p}"
  defp topic_for_scope({:swarm, w, s}), do: "swarm:#{w}:#{s}"
  defp topic_for_scope({:agent_config, a}), do: "agent_config:#{a}"
  defp topic_for_scope({:failover, w}), do: "failover:#{w}"
  defp topic_for_scope(:global), do: "events:global"
end
