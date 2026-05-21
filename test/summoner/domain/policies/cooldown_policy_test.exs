defmodule Summoner.Domain.Policies.CooldownPolicyTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Policies.CooldownPolicy

  describe "within_cooldown?/3" do
    test "nil last_fired_at is never in cooldown" do
      refute CooldownPolicy.within_cooldown?(nil, 60)
    end

    test "zero cooldown_s is never in cooldown" do
      refute CooldownPolicy.within_cooldown?(DateTime.utc_now(), 0)
    end

    test "within cooldown window" do
      now = DateTime.utc_now()
      last = DateTime.add(now, -30, :second)
      assert CooldownPolicy.within_cooldown?(last, 60, now)
    end

    test "past cooldown window" do
      now = DateTime.utc_now()
      last = DateTime.add(now, -61, :second)
      refute CooldownPolicy.within_cooldown?(last, 60, now)
    end

    test "exactly at cooldown boundary is not in cooldown" do
      now = DateTime.utc_now()
      last = DateTime.add(now, -60, :second)
      refute CooldownPolicy.within_cooldown?(last, 60, now)
    end

    test "1 second before cooldown expires is still in cooldown" do
      now = DateTime.utc_now()
      last = DateTime.add(now, -59, :second)
      assert CooldownPolicy.within_cooldown?(last, 60, now)
    end
  end
end
