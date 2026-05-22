defmodule Summoner.Domain.Policies.MemoryDecayTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Policies.MemoryDecay

  describe "apply_decay/3" do
    test "no decay when days_since_access is below interval" do
      assert MemoryDecay.apply_decay(1.0, 3) == 1.0
    end

    test "decays once after one interval" do
      result = MemoryDecay.apply_decay(1.0, 7)
      assert_in_delta result, 0.95, 0.001
    end

    test "decays twice after two intervals" do
      result = MemoryDecay.apply_decay(1.0, 14)
      assert_in_delta result, 0.95 * 0.95, 0.001
    end

    test "decays with custom factor and interval" do
      result = MemoryDecay.apply_decay(1.0, 10, decay_factor: 0.8, interval_days: 5)
      # 10 / 5 = 2 intervals, 0.8^2 = 0.64
      assert_in_delta result, 0.64, 0.001
    end

    test "never goes below 0.0" do
      result = MemoryDecay.apply_decay(0.01, 365)
      assert result >= 0.0
    end

    test "never exceeds 1.0" do
      result = MemoryDecay.apply_decay(1.0, 0)
      assert result <= 1.0
    end

    test "zero days means no decay" do
      assert MemoryDecay.apply_decay(0.5, 0) == 0.5
    end

    test "partial interval is not counted" do
      # 13 days / 7-day interval = 1 interval (integer division)
      result = MemoryDecay.apply_decay(1.0, 13)
      assert_in_delta result, 0.95, 0.001
    end
  end

  describe "should_prune?/2" do
    test "below default threshold" do
      assert MemoryDecay.should_prune?(0.05)
    end

    test "above default threshold" do
      refute MemoryDecay.should_prune?(0.5)
    end

    test "exactly at threshold is not pruned" do
      refute MemoryDecay.should_prune?(0.1)
    end

    test "custom threshold" do
      assert MemoryDecay.should_prune?(0.15, min_confidence: 0.2)
      refute MemoryDecay.should_prune?(0.25, min_confidence: 0.2)
    end
  end

  describe "defaults" do
    test "decay_factor is 0.95" do
      assert MemoryDecay.decay_factor() == 0.95
    end

    test "interval_days is 7" do
      assert MemoryDecay.interval_days() == 7
    end

    test "min_confidence is 0.1" do
      assert MemoryDecay.min_confidence() == 0.1
    end
  end
end
