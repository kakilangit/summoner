defmodule Summoner.Domain.Policies.RateLimitPolicy do
  @moduledoc """
  Pure policy for determining whether an event rule has exceeded its
  per-hour fire rate cap.

  No side effects — receives fire count, window start, and the cap,
  returns a boolean.
  """

  @doc """
  Returns true if the rule has exceeded its hourly fire rate limit.

  A `max_fires_per_hour` of 0 means no rate limit (unlimited).

  ## Parameters

    - `fire_count_in_window` — number of times the rule has fired in the current hour window
    - `max_fires_per_hour` — maximum allowed fires per hour (0 = unlimited)
  """
  @spec exceeded?(non_neg_integer(), non_neg_integer()) :: boolean()
  def exceeded?(_fire_count, 0), do: false
  def exceeded?(fire_count, max) when fire_count >= max, do: true
  def exceeded?(_fire_count, _max), do: false
end
