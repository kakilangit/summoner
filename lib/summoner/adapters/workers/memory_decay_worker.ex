defmodule Summoner.Adapters.Workers.MemoryDecayWorker do
  @moduledoc """
  Oban worker that runs daily to decay agent memory confidence
  and prune dead memories.

  1. Decays confidence for all memories not accessed within the
     decay interval (default: 7 days) by the configured factor
     (default: 0.95 per interval).
  2. Prunes memories below the minimum confidence threshold
     (default: 0.1) for each agent.
  3. Enforces per-agent memory cap (default: 500), removing
     lowest-confidence memories first.
  """

  use Oban.Worker, queue: :reaper, max_attempts: 1

  require Logger

  alias Summoner.Domain.Policies.MemoryDecay
  alias Summoner.Ports.Persistence.AgentMemories

  @default_max_memories 500

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    decay_factor = MemoryDecay.decay_factor()
    interval_days = MemoryDecay.interval_days()
    min_confidence = MemoryDecay.min_confidence()

    cutoff = DateTime.add(DateTime.utc_now(), -interval_days, :day)

    # Step 1: Decay confidence for stale memories (per-row interval calculation)
    {decayed_count, _} = AgentMemories.decay_batch(cutoff, decay_factor, interval_days)
    Logger.info("Memory decay: updated #{decayed_count} stale memories")

    # Step 2 & 3: Prune and cap per agent
    agent_ids = AgentMemories.list_agent_ids_with_memories()

    Enum.each(agent_ids, fn agent_id ->
      # Prune below threshold
      {pruned, _} = AgentMemories.prune_below(agent_id, min_confidence)

      if pruned > 0 do
        Logger.info("Memory decay: pruned #{pruned} dead memories for agent #{agent_id}")
      end

      # Enforce cap
      count = AgentMemories.count_by_agent(agent_id)

      if count > @default_max_memories do
        {capped, _} = AgentMemories.prune_excess(agent_id, @default_max_memories)
        Logger.info("Memory cap: removed #{capped} excess memories for agent #{agent_id}")
      end
    end)

    :ok
  end
end
