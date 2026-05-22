defmodule Summoner.Domain.Policies.MemoryDecay do
  @moduledoc """
  Pure decay calculation for agent memories.

  Confidence decays multiplicatively based on how many intervals
  have passed since the memory was last accessed.
  """

  @default_decay_factor 0.95
  @default_interval_days 7
  @default_min_confidence 0.1

  @doc """
  Calculates the new confidence after decay.

  ## Parameters

    - `confidence` — current confidence (0.0–1.0)
    - `days_since_access` — days since last access
    - `opts` — keyword list:
      - `:decay_factor` — multiplicative factor per interval (default 0.95)
      - `:interval_days` — how many days per decay interval (default 7)

  Returns the decayed confidence, clamped to [0.0, 1.0].
  """
  @spec apply_decay(float(), non_neg_integer(), keyword()) :: float()
  def apply_decay(confidence, days_since_access, opts \\ []) do
    factor = Keyword.get(opts, :decay_factor, @default_decay_factor)
    interval = Keyword.get(opts, :interval_days, @default_interval_days)

    intervals = div(days_since_access, interval)

    confidence
    |> Kernel.*(:math.pow(factor, intervals))
    |> max(0.0)
    |> min(1.0)
  end

  @doc "Returns the default minimum confidence threshold for pruning."
  @spec min_confidence() :: float()
  def min_confidence, do: @default_min_confidence

  @doc "Returns the default decay factor."
  @spec decay_factor() :: float()
  def decay_factor, do: @default_decay_factor

  @doc "Returns the default interval in days."
  @spec interval_days() :: non_neg_integer()
  def interval_days, do: @default_interval_days

  @doc """
  Returns true if the given confidence is below the pruning threshold.
  """
  @spec should_prune?(float(), keyword()) :: boolean()
  def should_prune?(confidence, opts \\ []) do
    threshold = Keyword.get(opts, :min_confidence, @default_min_confidence)
    confidence < threshold
  end
end
