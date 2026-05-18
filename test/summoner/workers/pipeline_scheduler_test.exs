defmodule Summoner.Workers.PipelineSchedulerTest do
  use Summoner.DataCase

  alias Summoner.Workers.PipelineScheduler

  describe "cron_matches?/2" do
    test "wildcard matches any value" do
      now = ~U[2026-05-05 14:30:00Z]
      assert PipelineScheduler.cron_matches?("* * * * *", now)
    end

    test "specific minute matches" do
      now = ~U[2026-05-05 14:30:00Z]
      assert PipelineScheduler.cron_matches?("30 * * * *", now)
      refute PipelineScheduler.cron_matches?("15 * * * *", now)
    end

    test "step values match" do
      now = ~U[2026-05-05 14:30:00Z]
      assert PipelineScheduler.cron_matches?("*/5 * * * *", now)
      assert PipelineScheduler.cron_matches?("*/10 * * * *", now)
      refute PipelineScheduler.cron_matches?("*/7 * * * *", now)
    end

    test "range values match" do
      now = ~U[2026-05-05 14:30:00Z]
      assert PipelineScheduler.cron_matches?("25-35 * * * *", now)
      refute PipelineScheduler.cron_matches?("0-10 * * * *", now)
    end

    test "comma-separated values match" do
      now = ~U[2026-05-05 14:30:00Z]
      assert PipelineScheduler.cron_matches?("0,15,30,45 * * * *", now)
      refute PipelineScheduler.cron_matches?("0,15,45 * * * *", now)
    end

    test "full expression matches" do
      # Tuesday May 5 2026 at 14:30
      now = ~U[2026-05-05 14:30:00Z]
      assert PipelineScheduler.cron_matches?("30 14 5 5 *", now)
      refute PipelineScheduler.cron_matches?("30 14 6 5 *", now)
    end

    test "nil expression returns false" do
      refute PipelineScheduler.cron_matches?(nil, ~U[2026-05-05 14:30:00Z])
    end
  end
end
