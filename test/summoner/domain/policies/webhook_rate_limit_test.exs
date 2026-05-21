defmodule Summoner.Domain.Policies.WebhookRateLimitTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Policies.WebhookRateLimit

  describe "check/2" do
    test "passes when nil rate limit" do
      assert :ok == WebhookRateLimit.check(%{rate_limit_rpm: nil}, [])
    end

    test "passes when under limit" do
      timestamps = [DateTime.utc_now()]
      assert :ok == WebhookRateLimit.check(%{rate_limit_rpm: 10}, timestamps)
    end

    test "fails when at limit" do
      timestamps = for _ <- 1..5, do: DateTime.utc_now()
      assert {:error, :rate_limited} == WebhookRateLimit.check(%{rate_limit_rpm: 5}, timestamps)
    end

    test "fails when over limit" do
      timestamps = for _ <- 1..10, do: DateTime.utc_now()
      assert {:error, :rate_limited} == WebhookRateLimit.check(%{rate_limit_rpm: 5}, timestamps)
    end
  end
end
