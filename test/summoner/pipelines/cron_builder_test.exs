defmodule Summoner.Pipelines.CronBuilderTest do
  use ExUnit.Case, async: true

  alias Summoner.Pipelines.CronBuilder

  describe "presets/0" do
    test "returns a non-empty list of presets" do
      presets = CronBuilder.presets()
      assert presets != []
      assert Enum.count(presets) <= 50
    end

    test "each preset has required fields" do
      for preset <- CronBuilder.presets() do
        assert is_binary(preset.key)
        assert is_binary(preset.label)
        assert is_binary(preset.group)
        assert is_binary(preset.cron)
      end
    end

    test "preset keys are unique" do
      keys = Enum.map(CronBuilder.presets(), & &1.key)
      assert keys == Enum.uniq(keys)
    end

    test "preset cron expressions are valid 5-field" do
      for preset <- CronBuilder.presets() do
        parts = String.split(preset.cron, " ")
        assert length(parts) == 5, "#{preset.key}: #{preset.cron} is not 5-field"
      end
    end
  end

  describe "preset_options/0" do
    test "returns grouped options with Custom at the end" do
      options = CronBuilder.preset_options()
      assert is_list(options)
      {last_group, last_items} = List.last(options)
      assert last_group == "Advanced"
      assert {"Custom cron expression", "custom"} in last_items
    end
  end

  describe "preset_for/1" do
    test "returns preset key for known cron expression" do
      refute CronBuilder.preset_for("*/5 * * * *") == "custom"
    end

    test "returns custom for unknown cron expression" do
      assert CronBuilder.preset_for("13 3 * * 2") == "custom"
    end

    test "returns default for nil" do
      assert CronBuilder.preset_for(nil) == "every_5m"
    end

    test "returns default for empty string" do
      assert CronBuilder.preset_for("") == "every_5m"
    end
  end

  describe "to_human/1" do
    test "returns empty string for nil" do
      assert CronBuilder.to_human(nil) == ""
    end

    test "returns empty string for empty" do
      assert CronBuilder.to_human("") == ""
    end

    test "returns preset label for known expressions" do
      assert CronBuilder.to_human("*/5 * * * *") == "Every 5 minutes"
      assert CronBuilder.to_human("0 * * * *") == "Every hour"
      assert CronBuilder.to_human("0 0 * * *") == "Daily at midnight"
      assert CronBuilder.to_human("0 9 * * 1") == "Monday at 9:00 AM"
      assert CronBuilder.to_human("0 9 * * 1-5") == "Weekdays at 9:00 AM"
      assert CronBuilder.to_human("0 0 1 * *") == "1st of month at midnight"
    end

    test "parses non-preset cron to human-readable" do
      assert CronBuilder.to_human("30 14 * * *") == "Daily at 2:30 PM"
      assert CronBuilder.to_human("0 8 * * 3") == "Daily at 8:00 AM, on Wednesday"
    end

    test "handles step expressions" do
      assert CronBuilder.to_human("*/10 * * * *") == "Every 10 minutes"
      assert CronBuilder.to_human("0 */4 * * *") == "Every 4 hours"
    end

    test "handles every minute" do
      assert CronBuilder.to_human("* * * * *") == "Every minute"
    end

    test "handles noon" do
      assert CronBuilder.to_human("0 12 * * *") == "Daily at noon"
    end

    test "handles weekends" do
      assert CronBuilder.to_human("0 10 * * 0,6") == "Weekends at 10:00 AM"
    end

    test "handles day of month" do
      assert CronBuilder.to_human("0 0 15 * *") == "15th of month at midnight"
    end

    test "includes month when specified" do
      result = CronBuilder.to_human("0 0 1 6 *")
      assert result =~ "Jun"
    end
  end
end
