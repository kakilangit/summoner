defmodule Summoner.Workers.CompactorJob do
  @moduledoc """
  Oban worker that runs conversation compaction asynchronously.

  Enqueued after an invocation completes if the conversation has
  accumulated enough messages to warrant summarization.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    unique: [keys: [:conversation_id], states: [:available, :scheduled, :executing]]

  alias Summoner.Agents
  alias Summoner.Compactor
  alias Summoner.Providers.Provider

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "conversation_id" => conversation_id,
          "agent_id" => agent_id
        }
      }) do
    agent = Agents.get_agent_with_provider!(agent_id)

    provider = %{
      kind: agent.local_agent.provider.kind,
      api_format: agent.local_agent.provider.api_format,
      base_url: agent.local_agent.provider.base_url,
      api_key: Provider.api_key(agent.local_agent.provider),
      model: agent.local_agent.model
    }

    case Compactor.maybe_compact(conversation_id, provider) do
      :ok -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
