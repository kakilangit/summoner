defmodule Summoner.Services.Plugins.EventSerializer do
  @moduledoc """
  Converts domain event structs into the plugin contract format.

  Each event type has an explicit serializer that produces the exact
  JSON shape defined in `priv/openapi/plugin_contract.yaml`.

  This replaces the generic `Map.from_struct |> stringify_keys` approach
  to enforce a stable, typed contract between Summoner and plugins.
  """

  alias Summoner.Domain.Events.{
    AgentConfigChanged,
    Failover,
    InvocationCompleted,
    InvocationFailed,
    InvocationStarted,
    MediaGenerationCompleted,
    MediaGenerationFailed,
    MediaGenerationStarted,
    PipelineRunStatus,
    PipelineStageStatus,
    SwarmDone,
    SwarmTimeout,
    SwarmTurn,
    WebhookFailed,
    WebhookTriggered
  }

  @doc """
  Serialize a domain event struct to the plugin contract payload.

  Returns `{event_type, data}` where `data` matches the OpenAPI schema
  for that event type, or `nil` if the event is not forwarded to plugins.
  """
  @spec serialize(struct()) :: {String.t(), map()} | nil

  def serialize(%InvocationStarted{} = e) do
    {"invocation.started",
     %{
       "event_type" => "invocation.started",
       "workspace_id" => e.workspace_id,
       "agent_id" => e.agent_id,
       "invocation_id" => e.invocation_id,
       "conversation_id" => e.conversation_id
     }}
  end

  def serialize(%InvocationCompleted{} = e) do
    {"invocation.completed",
     %{
       "event_type" => "invocation.completed",
       "workspace_id" => e.workspace_id,
       "agent_id" => e.agent_id,
       "invocation_id" => e.invocation_id,
       "conversation_id" => e.conversation_id,
       "response" => get_in(e.output || %{}, ["response"])
     }}
  end

  def serialize(%InvocationFailed{} = e) do
    {"invocation.failed",
     %{
       "event_type" => "invocation.failed",
       "workspace_id" => e.workspace_id,
       "agent_id" => e.agent_id,
       "invocation_id" => e.invocation_id,
       "conversation_id" => e.conversation_id,
       "error" => get_in(e.output || %{}, ["error"])
     }}
  end

  def serialize(%PipelineRunStatus{} = e) do
    {"pipeline.started",
     %{
       "event_type" => "pipeline.started",
       "workspace_id" => e.workspace_id,
       "pipeline_id" => e.pipeline_id,
       "run_id" => e.run_id,
       "status" => to_string(e.status)
     }}
  end

  def serialize(%PipelineStageStatus{} = e) do
    {"pipeline.completed",
     %{
       "event_type" => "pipeline.completed",
       "workspace_id" => e.workspace_id,
       "pipeline_id" => e.pipeline_id,
       "run_id" => e.run_id,
       "position" => e.position,
       "status" => to_string(e.status)
     }}
  end

  def serialize(%SwarmTurn{} = e) do
    {"swarm.turn",
     %{
       "event_type" => "swarm.turn",
       "workspace_id" => e.workspace_id,
       "swarm_id" => e.swarm_id,
       "conversation_id" => e.conversation_id,
       "agent_id" => e.agent_id
     }}
  end

  def serialize(%SwarmDone{} = e) do
    {"swarm.done",
     %{
       "event_type" => "swarm.done",
       "workspace_id" => e.workspace_id,
       "swarm_id" => e.swarm_id,
       "conversation_id" => e.conversation_id,
       "summary" => e.summary
     }}
  end

  def serialize(%SwarmTimeout{} = e) do
    {"swarm.timeout",
     %{
       "event_type" => "swarm.timeout",
       "workspace_id" => e.workspace_id,
       "swarm_id" => e.swarm_id,
       "conversation_id" => e.conversation_id,
       "agent_id" => e.agent_id
     }}
  end

  def serialize(%WebhookTriggered{} = e) do
    {"webhook.triggered",
     %{
       "event_type" => "webhook.triggered",
       "workspace_id" => e.workspace_id,
       "webhook_id" => e.webhook_id,
       "response_mode" => to_string(e.response_mode),
       "invocation_id" => e.invocation_id,
       "timestamp" => maybe_iso8601(e.timestamp)
     }}
  end

  def serialize(%WebhookFailed{} = e) do
    {"webhook.failed",
     %{
       "event_type" => "webhook.failed",
       "workspace_id" => e.workspace_id,
       "webhook_id" => e.webhook_id,
       "error_reason" => to_string(e.error_reason),
       "timestamp" => maybe_iso8601(e.timestamp)
     }}
  end

  def serialize(%Failover{} = e) do
    {"failover",
     %{
       "event_type" => "failover",
       "workspace_id" => e.workspace_id,
       "invocation_id" => e.invocation_id,
       "from_agent_id" => e.from_agent_id,
       "to_agent_id" => e.to_agent_id,
       "reason" => e.reason,
       "depth" => e.depth
     }}
  end

  def serialize(%MediaGenerationStarted{} = e) do
    {"media.started",
     %{
       "event_type" => "media.started",
       "workspace_id" => e.workspace_id,
       "conversation_id" => e.conversation_id,
       "attachment_id" => e.attachment_id,
       "type" => e.type,
       "prompt" => e.prompt
     }}
  end

  def serialize(%MediaGenerationCompleted{} = e) do
    {"media.completed",
     %{
       "event_type" => "media.completed",
       "workspace_id" => e.workspace_id,
       "conversation_id" => e.conversation_id,
       "attachment_id" => e.attachment_id,
       "url" => e.url
     }}
  end

  def serialize(%MediaGenerationFailed{} = e) do
    {"media.failed",
     %{
       "event_type" => "media.failed",
       "workspace_id" => e.workspace_id,
       "conversation_id" => e.conversation_id,
       "attachment_id" => e.attachment_id,
       "error" => e.error
     }}
  end

  def serialize(%AgentConfigChanged{} = e) do
    {"agent.config_changed",
     %{
       "event_type" => "agent.config_changed",
       "agent_id" => e.agent_id
     }}
  end

  def serialize(_event), do: nil

  defp maybe_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp maybe_iso8601(_), do: nil
end
