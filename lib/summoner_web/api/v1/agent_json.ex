defmodule SummonerWeb.API.V1.AgentJSON do
  @moduledoc "JSON rendering for agents."

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.LocalAgent
  alias Summoner.Domain.Schemas.RemoteAgent

  def index(%{agents: agents}) do
    %{data: Enum.map(agents, &agent_data/1)}
  end

  def show(%{agent: agent}) do
    %{data: agent_data(agent)}
  end

  defp agent_data(%Agent{} = agent) do
    base = %{
      id: agent.id,
      name: agent.name,
      callname: agent.callname,
      type: agent.type,
      role: agent.role,
      workspace_id: agent.workspace_id,
      inserted_at: agent.inserted_at,
      updated_at: agent.updated_at
    }

    case agent.type do
      :local -> Map.put(base, :local_agent, local_agent_data(agent.local_agent))
      :remote -> Map.put(base, :remote_agent, remote_agent_data(agent.remote_agent))
      _other -> base
    end
  end

  defp local_agent_data(%LocalAgent{} = la) do
    %{
      model: la.model,
      system_prompt: la.system_prompt,
      personality: la.personality,
      max_steps: la.max_steps,
      max_concurrent_invocations: la.max_concurrent_invocations,
      max_delegation_concurrency: la.max_delegation_concurrency,
      max_tokens_per_invocation: la.max_tokens_per_invocation,
      context_length: la.context_length,
      step_timeout_s: la.step_timeout_s,
      total_timeout_s: la.total_timeout_s,
      stream_tokens_to_observability: la.stream_tokens_to_observability,
      budget_usd: la.budget_usd,
      max_tool_concurrency: la.max_tool_concurrency,
      provider_id: la.provider_id,
      media_provider_id: la.media_provider_id
    }
  end

  defp local_agent_data(_), do: nil

  defp remote_agent_data(%RemoteAgent{} = ra) do
    %{
      agent_card_url: ra.agent_card_url,
      auth_mode: ra.auth_mode,
      status: ra.status,
      timeout_s: ra.timeout_s,
      card_refreshed_at: ra.card_refreshed_at,
      api_key_secret_id: ra.api_key_secret_id
    }
  end

  defp remote_agent_data(_), do: nil
end
