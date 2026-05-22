defmodule Summoner.Domain.Policies.CooldownPolicy do
  @moduledoc """
  Pure policy for determining whether an event rule is within its cooldown window.

  No side effects — receives timestamps and cooldown config, returns a boolean.
  """

  @doc """
  Returns true if the rule is still within its cooldown window and should NOT fire.

  ## Parameters

    - `last_fired_at` — the last time the rule fired (nil if never fired)
    - `cooldown_s` — cooldown window in seconds (0 means no cooldown)
    - `now` — current time (defaults to `DateTime.utc_now/0`)

  ## Examples

      iex> within_cooldown?(nil, 60)
      false

      iex> within_cooldown?(~U[2026-01-01 00:00:00Z], 0)
      false

      iex> within_cooldown?(~U[2026-01-01 00:00:00Z], 60, ~U[2026-01-01 00:00:30Z])
      true

      iex> within_cooldown?(~U[2026-01-01 00:00:00Z], 60, ~U[2026-01-01 00:01:01Z])
      false
  """
  @spec within_cooldown?(DateTime.t() | nil, non_neg_integer(), DateTime.t()) :: boolean()
  def within_cooldown?(last_fired_at, cooldown_s, now \\ DateTime.utc_now())

  def within_cooldown?(nil, _cooldown_s, _now), do: false
  def within_cooldown?(_last_fired_at, 0, _now), do: false

  def within_cooldown?(last_fired_at, cooldown_s, now) do
    DateTime.diff(now, last_fired_at, :second) < cooldown_s
  end
end
