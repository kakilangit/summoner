defmodule Summoner.Broadcasts do
  @moduledoc """
  PubSub broadcast helpers.

  Provides topic builders, subscribe/broadcast wrappers, and typed
  message constructors for the invocation and agent event system.

  All broadcasts are fire-and-forget — callers never block on delivery.
  """

  @pubsub Summoner.PubSub

  # -------------------------------------------------------------------
  # Topic builders
  # -------------------------------------------------------------------

  @doc """
  Topic for a specific invocation's lifecycle events.

  Subscribers receive:
  - `{:invocation_status, invocation_id, status}`
  - `{:invocation_step, step}`
  """
  def invocation_topic(workspace_id, invocation_id) do
    "invocation:#{workspace_id}:#{invocation_id}"
  end

  @doc """
  Topic for invocation events (tool started/finished/failed).

  Subscribers receive:
  - `{:invocation_event, event}`
  """
  def invocation_events_topic(workspace_id, invocation_id) do
    "invocation_events:#{workspace_id}:#{invocation_id}"
  end

  @doc """
  Topic for an agent's activity feed.

  Subscribers receive:
  - `{:agent_invocation, invocation}`
  - `{:content_token, invocation_id, token}`
  """
  def agent_topic(workspace_id, agent_id) do
    "agent:#{workspace_id}:#{agent_id}"
  end

  @doc """
  Topic for workspace-level escalation events.

  Subscribers receive:
  - `{:escalation, invocation_id, reason}`
  """
  def escalations_topic(workspace_id) do
    "escalations:#{workspace_id}"
  end

  @doc """
  Topic for pipeline run lifecycle events.

  Subscribers receive:
  - `{:pipeline_run_status, run_id, status}`
  - `{:pipeline_run_stage_status, run_id, position, status}`
  """
  def pipeline_topic(workspace_id, pipeline_id) do
    "pipeline:#{workspace_id}:#{pipeline_id}"
  end

  @doc """
  Topic for provider lifecycle events (e.g. Copilot device code connect).

  Subscribers receive:
  - `{:copilot_connect, :ok | {:error, reason}}`
  """
  def provider_topic(workspace_id, provider_id) do
    "provider:#{workspace_id}:#{provider_id}"
  end

  @doc """
  Topic for swarm turn routing events.

  Subscribers receive:
  - `{:swarm_turn, conversation_id, agent_id}` — next agent is responding
  - `{:swarm_done, conversation_id, summary}` — turn cycle complete
  - `{:swarm_timeout, conversation_id, agent_id}` — agent timed out
  """
  def swarm_topic(workspace_id, swarm_id) do
    "swarm:#{workspace_id}:#{swarm_id}"
  end

  @doc """
  Topic for conversation-level events (media generation lifecycle).

  Subscribers receive:
  - `{:media_generation_started, conversation_id, %{attachment_id, type, prompt}}`
  - `{:media_generation_complete, conversation_id, %{attachment_id, url}}`
  - `{:media_generation_failed, conversation_id, %{attachment_id, error}}`
  """
  def conversation_topic(workspace_id, conversation_id) do
    "conversation:#{workspace_id}:#{conversation_id}"
  end

  # -------------------------------------------------------------------
  # Subscribe / Broadcast
  # -------------------------------------------------------------------

  @doc """
  Subscribes the calling process to a topic.
  """
  def subscribe(topic) do
    Phoenix.PubSub.subscribe(@pubsub, topic)
  end

  @doc """
  Unsubscribes from a PubSub topic.
  """
  def unsubscribe(topic) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic)
  end

  @doc """
  Broadcasts a message to a topic. Fire-and-forget.
  """
  def broadcast(topic, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic, message)
  end

  # -------------------------------------------------------------------
  # Typed broadcasts
  # -------------------------------------------------------------------

  @doc """
  Broadcasts an invocation status change.
  """
  def broadcast_invocation_status(workspace_id, invocation_id, status) do
    broadcast(
      invocation_topic(workspace_id, invocation_id),
      {:invocation_status, invocation_id, status}
    )
  end

  @doc """
  Broadcasts an invocation step (after persistence).
  """
  def broadcast_invocation_step(workspace_id, invocation_id, step) do
    broadcast(
      invocation_topic(workspace_id, invocation_id),
      {:invocation_step, step}
    )
  end

  @doc """
  Broadcasts an invocation event (tool_started, tool_finished, etc.).
  """
  def broadcast_invocation_event(workspace_id, invocation_id, event) do
    broadcast(
      invocation_events_topic(workspace_id, invocation_id),
      {:invocation_event, event}
    )
  end

  @doc """
  Broadcasts a content token to an agent's activity feed.

  Only call this when the agent's `stream_tokens_to_observability` is true.
  """
  def broadcast_content_token(workspace_id, agent_id, invocation_id, token) do
    broadcast(
      agent_topic(workspace_id, agent_id),
      {:content_token, invocation_id, token}
    )
  end

  @doc """
  Broadcasts an escalation event to the workspace.
  """
  def broadcast_escalation(workspace_id, invocation_id, reason) do
    broadcast(
      escalations_topic(workspace_id),
      {:escalation, invocation_id, reason}
    )
  end
end
