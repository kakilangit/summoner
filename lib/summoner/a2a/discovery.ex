defmodule Summoner.A2A.Discovery do
  @moduledoc """
  Agent Card discovery and caching for remote A2A agents.

  Wraps `A2A.Client.discover/2` with TTL-based caching against the
  `remote_agents.cached_agent_card` / `card_refreshed_at` fields.
  """

  require Logger

  alias Summoner.Agents.RemoteAgent
  alias Summoner.Repo

  @default_ttl_seconds 3_600

  @doc """
  Fetches the Agent Card from a remote URL.

  Returns `{:ok, %A2A.AgentCard{}}` or `{:error, reason}`.
  """
  def fetch_agent_card(base_url, opts \\ []) do
    case A2A.Client.discover(base_url, opts) do
      {:ok, %A2A.AgentCard{}} = result -> result
      {:error, _} = error -> error
    end
  end

  @doc """
  Returns the cached Agent Card if fresh, otherwise re-fetches and persists.

  The TTL defaults to #{@default_ttl_seconds} seconds.
  Returns `{:ok, %A2A.AgentCard{}}` or `{:error, reason}`.
  """
  def get_or_refresh(%RemoteAgent{} = remote_agent, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl_seconds)

    if fresh?(remote_agent, ttl) do
      {:ok, decode_cached_card(remote_agent.cached_agent_card)}
    else
      refresh(remote_agent, opts)
    end
  end

  @doc """
  Forces a re-fetch of the Agent Card and updates the remote_agent record.

  Returns `{:ok, %A2A.AgentCard{}}` or `{:error, reason}`.
  """
  def refresh(%RemoteAgent{} = remote_agent, opts \\ []) do
    case fetch_agent_card(remote_agent.agent_card_url, opts) do
      {:ok, %A2A.AgentCard{} = card} ->
        persist_card(remote_agent, card)
        {:ok, card}

      {:error, reason} ->
        Logger.warning(
          "Failed to refresh Agent Card for #{remote_agent.agent_card_url}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp fresh?(%RemoteAgent{card_refreshed_at: nil}, _ttl), do: false

  defp fresh?(%RemoteAgent{cached_agent_card: nil}, _ttl), do: false

  defp fresh?(%RemoteAgent{card_refreshed_at: refreshed_at}, ttl) do
    cutoff = DateTime.add(DateTime.utc_now(), -ttl, :second)
    DateTime.compare(refreshed_at, cutoff) == :gt
  end

  defp persist_card(%RemoteAgent{} = remote_agent, %A2A.AgentCard{} = card) do
    remote_agent
    |> Ecto.Changeset.change(%{
      cached_agent_card: encode_card(card),
      card_refreshed_at: DateTime.utc_now(),
      status: :online
    })
    |> Repo.update()
  end

  defp encode_card(%A2A.AgentCard{} = card) do
    %{
      "name" => card.name,
      "description" => card.description,
      "url" => card.url,
      "version" => card.version,
      "skills" => Enum.map(card.skills || [], &encode_skill/1),
      "capabilities" => encode_capabilities(card.capabilities),
      "defaultInputModes" => card.default_input_modes,
      "defaultOutputModes" => card.default_output_modes,
      "provider" => card.provider
    }
  end

  defp encode_skill(skill) when is_map(skill) do
    %{
      "id" => Map.get(skill, :id, Map.get(skill, "id")),
      "name" => Map.get(skill, :name, Map.get(skill, "name")),
      "description" => Map.get(skill, :description, Map.get(skill, "description")),
      "tags" => Map.get(skill, :tags, Map.get(skill, "tags", []))
    }
  end

  defp encode_capabilities(nil), do: %{}

  defp encode_capabilities(caps) when is_map(caps) do
    %{
      "streaming" => Map.get(caps, :streaming, Map.get(caps, "streaming", false)),
      "pushNotifications" =>
        Map.get(caps, :push_notifications, Map.get(caps, "pushNotifications", false)),
      "stateTransitionHistory" =>
        Map.get(
          caps,
          :state_transition_history,
          Map.get(caps, "stateTransitionHistory", false)
        )
    }
  end

  defp decode_cached_card(data) when is_map(data) do
    # Return a lightweight struct-like map; callers use card.name, etc.
    %A2A.AgentCard{
      name: data["name"],
      description: data["description"],
      url: data["url"],
      version: data["version"],
      skills: [],
      default_input_modes: data["defaultInputModes"] || ["text"],
      default_output_modes: data["defaultOutputModes"] || ["text"]
    }
  end
end
