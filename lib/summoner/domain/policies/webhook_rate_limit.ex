defmodule Summoner.Domain.Policies.WebhookRateLimit do
  @moduledoc """
  Pure rate limit check for webhook triggers.

  Evaluates whether a webhook has exceeded its configured RPM
  based on recent trigger timestamps.
  """

  @doc """
  Check if a webhook trigger is within rate limits.

  `recent_timestamps` should be a list of trigger timestamps within the
  current 60-second window.
  """
  @spec check(struct(), [DateTime.t()]) :: :ok | {:error, :rate_limited}
  def check(%{rate_limit_rpm: nil}, _timestamps), do: :ok

  def check(%{rate_limit_rpm: limit}, recent_timestamps) do
    if length(recent_timestamps) >= limit do
      {:error, :rate_limited}
    else
      :ok
    end
  end
end
