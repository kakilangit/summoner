defmodule Summoner.Domain.Policies.CircuitBreakerPolicy do
  @moduledoc """
  Pure policy for event rule circuit breaker logic.

  Disables rules after N consecutive failures and determines when
  they can be re-enabled after a backoff period.

  No side effects — receives failure counts and timestamps, returns decisions.
  """

  @max_consecutive_failures 5
  @base_backoff_s 60

  @doc """
  Returns true if the circuit is open (rule should be skipped).

  The circuit opens after `@max_consecutive_failures` consecutive failures.
  It stays open until `disabled_until` has passed.
  """
  @spec open?(non_neg_integer(), DateTime.t() | nil, DateTime.t()) :: boolean()
  def open?(consecutive_failures, disabled_until, now \\ DateTime.utc_now())

  def open?(failures, _disabled_until, _now) when failures < @max_consecutive_failures, do: false

  def open?(_failures, nil, _now), do: true

  def open?(_failures, disabled_until, now) do
    DateTime.compare(now, disabled_until) == :lt
  end

  @doc """
  Returns true if a rule should be tripped (circuit opened) based on
  the new consecutive failure count.
  """
  @spec should_trip?(non_neg_integer()) :: boolean()
  def should_trip?(consecutive_failures) do
    consecutive_failures >= @max_consecutive_failures
  end

  @doc """
  Calculates the `disabled_until` timestamp using exponential backoff.

  Backoff = base * 2^(failures - max_failures), capped at 1 hour.
  """
  @spec backoff_until(non_neg_integer(), DateTime.t()) :: DateTime.t()
  def backoff_until(consecutive_failures, now \\ DateTime.utc_now()) do
    exponent = max(0, consecutive_failures - @max_consecutive_failures)
    backoff_s = min(@base_backoff_s * Integer.pow(2, exponent), 3600)
    DateTime.add(now, backoff_s, :second)
  end

  @doc "Returns the threshold for consecutive failures."
  @spec max_consecutive_failures() :: non_neg_integer()
  def max_consecutive_failures, do: @max_consecutive_failures
end
