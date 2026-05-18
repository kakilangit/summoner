defmodule Summoner.TimeZoneTest do
  use ExUnit.Case, async: true

  alias Summoner.TimeZone

  describe "local_timezone/0" do
    test "returns configured timezone" do
      assert TimeZone.local_timezone() == "Europe/Berlin"
    end
  end

  describe "to_local/1" do
    test "converts UTC datetime to local timezone" do
      {:ok, utc} = DateTime.new(~D[2026-06-15], ~T[12:00:00], "Etc/UTC")
      local = TimeZone.to_local(utc)

      assert local.time_zone == "Europe/Berlin"
      # June = CEST = UTC+2
      assert local.hour == 14
    end

    test "handles winter time (CET = UTC+1)" do
      {:ok, utc} = DateTime.new(~D[2026-01-15], ~T[12:00:00], "Etc/UTC")
      local = TimeZone.to_local(utc)

      assert local.time_zone == "Europe/Berlin"
      assert local.hour == 13
    end

    test "converts NaiveDateTime" do
      ndt = ~N[2026-06-15 12:00:00]
      local = TimeZone.to_local(ndt)

      assert local.time_zone == "Europe/Berlin"
      assert local.hour == 14
    end

    test "returns nil for nil" do
      assert TimeZone.to_local(nil) == nil
    end
  end

  describe "format/2" do
    test "formats with timezone abbreviation by default" do
      {:ok, utc} = DateTime.new(~D[2026-06-15], ~T[12:00:00], "Etc/UTC")
      result = TimeZone.format(utc)

      assert result == "2026-06-15 14:00 CEST"
    end

    test "uses custom format" do
      {:ok, utc} = DateTime.new(~D[2026-06-15], ~T[12:00:00], "Etc/UTC")
      result = TimeZone.format(utc, format: "%H:%M:%S")

      assert result == "14:00:00 CEST"
    end

    test "hides timezone when show_zone is false" do
      {:ok, utc} = DateTime.new(~D[2026-06-15], ~T[12:00:00], "Etc/UTC")
      result = TimeZone.format(utc, format: "%H:%M", show_zone: false)

      assert result == "14:00"
    end

    test "returns empty string for nil" do
      assert TimeZone.format(nil) == ""
    end

    test "formats winter time as CET" do
      {:ok, utc} = DateTime.new(~D[2026-01-15], ~T[12:00:00], "Etc/UTC")
      result = TimeZone.format(utc)

      assert result == "2026-01-15 13:00 CET"
    end
  end

  describe "format_chat_timestamp/1" do
    test "shows time only for today" do
      # Build a UTC time that is "now" in local timezone
      now_utc = DateTime.utc_now()
      result = TimeZone.format_chat_timestamp(now_utc)

      # Should be just HH:MM
      assert Regex.match?(~r/^\d{2}:\d{2}$/, result)
    end

    test "shows 'Yesterday HH:MM' for yesterday" do
      utc = DateTime.utc_now() |> DateTime.add(-1, :day)
      result = TimeZone.format_chat_timestamp(utc)

      assert result =~ ~r/^Yesterday \d{2}:\d{2}$/
    end

    test "shows 'N days ago HH:MM' for 2-6 days ago" do
      utc = DateTime.utc_now() |> DateTime.add(-3, :day)
      result = TimeZone.format_chat_timestamp(utc)

      assert result =~ ~r/^3 days ago \d{2}:\d{2}$/
    end

    test "shows date for 7+ days ago" do
      utc = DateTime.utc_now() |> DateTime.add(-10, :day)
      result = TimeZone.format_chat_timestamp(utc)

      # Should be like "May 1, 14:32"
      assert result =~ ~r/^[A-Z][a-z]+ \d+, \d{2}:\d{2}$/
    end

    test "returns empty string for nil" do
      assert TimeZone.format_chat_timestamp(nil) == ""
    end
  end
end
