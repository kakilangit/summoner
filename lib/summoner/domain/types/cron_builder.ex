defmodule Summoner.Domain.Types.CronBuilder do
  @moduledoc """
  Converts between user-friendly schedule presets and cron expressions.

  Provides a two-tier UX:
  - **Presets** — common schedules selectable from a dropdown
  - **Custom** — raw 5-field cron for advanced users

  Also converts any cron expression into a human-readable description
  for display on index/show pages.
  """

  @max_presets 50

  @type preset :: %{
          key: String.t(),
          label: String.t(),
          group: String.t(),
          cron: String.t()
        }

  @presets [
    # Minutes
    %{key: "every_1m", label: "Every minute", group: "Minutes", cron: "* * * * *"},
    %{key: "every_5m", label: "Every 5 minutes", group: "Minutes", cron: "*/5 * * * *"},
    %{key: "every_10m", label: "Every 10 minutes", group: "Minutes", cron: "*/10 * * * *"},
    %{key: "every_15m", label: "Every 15 minutes", group: "Minutes", cron: "*/15 * * * *"},
    %{key: "every_30m", label: "Every 30 minutes", group: "Minutes", cron: "*/30 * * * *"},
    # Hours
    %{key: "every_1h", label: "Every hour", group: "Hours", cron: "0 * * * *"},
    %{key: "every_2h", label: "Every 2 hours", group: "Hours", cron: "0 */2 * * *"},
    %{key: "every_4h", label: "Every 4 hours", group: "Hours", cron: "0 */4 * * *"},
    %{key: "every_6h", label: "Every 6 hours", group: "Hours", cron: "0 */6 * * *"},
    %{key: "every_12h", label: "Every 12 hours", group: "Hours", cron: "0 */12 * * *"},
    # Daily
    %{key: "daily_midnight", label: "Daily at midnight", group: "Daily", cron: "0 0 * * *"},
    %{key: "daily_6am", label: "Daily at 6:00 AM", group: "Daily", cron: "0 6 * * *"},
    %{key: "daily_9am", label: "Daily at 9:00 AM", group: "Daily", cron: "0 9 * * *"},
    %{key: "daily_noon", label: "Daily at noon", group: "Daily", cron: "0 12 * * *"},
    %{key: "daily_6pm", label: "Daily at 6:00 PM", group: "Daily", cron: "0 18 * * *"},
    # Weekly
    %{key: "weekly_mon_9am", label: "Monday at 9:00 AM", group: "Weekly", cron: "0 9 * * 1"},
    %{key: "weekly_fri_5pm", label: "Friday at 5:00 PM", group: "Weekly", cron: "0 17 * * 5"},
    %{key: "weekdays_9am", label: "Weekdays at 9:00 AM", group: "Weekly", cron: "0 9 * * 1-5"},
    %{key: "weekends_10am", label: "Weekends at 10:00 AM", group: "Weekly", cron: "0 10 * * 0,6"},
    # Monthly
    %{key: "monthly_1st", label: "1st of month at midnight", group: "Monthly", cron: "0 0 1 * *"},
    %{
      key: "monthly_15th",
      label: "15th of month at midnight",
      group: "Monthly",
      cron: "0 0 15 * *"
    }
  ]

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc "Returns all schedule presets, grouped for UI display."
  @spec presets :: [preset()]
  def presets, do: Enum.take(@presets, @max_presets)

  @doc """
  Returns presets as `{label, cron}` options grouped by category
  for use in a select input, with a Custom option appended.
  """
  @spec preset_options :: [{String.t(), String.t() | [{String.t(), String.t()}]}]
  def preset_options do
    grouped =
      @presets
      |> Enum.take(@max_presets)
      |> Enum.group_by(& &1.group)
      |> Enum.sort_by(fn {group, _} -> group_order(group) end)
      |> Enum.map(fn {group, items} ->
        {group, Enum.map(items, fn p -> {p.label, p.cron} end)}
      end)

    grouped ++ [{"Advanced", [{"Custom cron expression", "custom"}]}]
  end

  @doc """
  Finds the preset key matching a cron expression, or "custom".
  """
  @spec preset_for(String.t() | nil) :: String.t()
  def preset_for(nil), do: "every_5m"
  def preset_for(""), do: "every_5m"

  def preset_for(cron) do
    case Enum.find(@presets, fn p -> p.cron == cron end) do
      %{key: key} -> key
      nil -> "custom"
    end
  end

  @doc """
  Returns the cron expression for a preset key, or nil for "custom".
  """
  @spec cron_for_preset(String.t()) :: String.t() | nil
  def cron_for_preset(key) do
    case Enum.find(@presets, fn p -> p.key == key end) do
      %{cron: cron} -> cron
      nil -> nil
    end
  end

  @doc """
  Converts a 5-field cron expression into a human-readable description.

  Returns the raw expression if it can't be parsed into a friendly string.
  """
  @spec to_human(String.t() | nil) :: String.t()
  def to_human(nil), do: ""
  def to_human(""), do: ""

  def to_human(cron) do
    # Check presets first (exact match)
    case Enum.find(@presets, fn p -> p.cron == cron end) do
      %{label: label} -> label
      nil -> parse_to_human(cron)
    end
  end

  # -------------------------------------------------------------------
  # Human-readable parser
  # -------------------------------------------------------------------

  defp parse_to_human(cron) do
    case String.split(cron, ~r/\s+/, trim: true) do
      [minute, hour, day, month, weekday] ->
        build_description(minute, hour, day, month, weekday)

      _ ->
        cron
    end
  end

  defp build_description(minute, hour, day, month, weekday) do
    time_part = describe_time(minute, hour)

    [time_part]
    |> maybe_append(day != "*", fn -> day_desc(day) end)
    |> maybe_append(month != "*", fn -> month_desc(month) end)
    |> maybe_append(weekday != "*", fn -> weekday_desc(weekday) end)
    |> Enum.join(", ")
  end

  defp describe_time("*", "*"), do: "Every minute"
  defp describe_time("*/" <> step, "*"), do: "Every #{step} minutes"
  defp describe_time("0", "*"), do: "Every hour"
  defp describe_time("0", "*/" <> step), do: "Every #{step} hours"
  defp describe_time("0", h) when byte_size(h) <= 2, do: "Daily at #{format_time(h, "0")}"

  defp describe_time(m, h) when byte_size(h) <= 2 and byte_size(m) <= 2 do
    "Daily at #{format_time(h, m)}"
  end

  defp describe_time(m, h), do: "#{cron_field_desc("minute", m)}, #{cron_field_desc("hour", h)}"

  defp maybe_append(parts, true, fun), do: parts ++ [fun.()]
  defp maybe_append(parts, false, _fun), do: parts

  defp format_time(hour, minute) do
    h = safe_int(hour)
    m = safe_int(minute)

    cond do
      h == 0 and m == 0 -> "midnight"
      h == 12 and m == 0 -> "noon"
      h < 12 -> "#{h}:#{String.pad_leading("#{m}", 2, "0")} AM"
      h == 12 -> "12:#{String.pad_leading("#{m}", 2, "0")} PM"
      true -> "#{h - 12}:#{String.pad_leading("#{m}", 2, "0")} PM"
    end
  end

  defp day_desc(day) do
    case day do
      "1" -> "on the 1st"
      "15" -> "on the 15th"
      d -> "on day #{d}"
    end
  end

  @month_names %{
    "1" => "Jan",
    "2" => "Feb",
    "3" => "Mar",
    "4" => "Apr",
    "5" => "May",
    "6" => "Jun",
    "7" => "Jul",
    "8" => "Aug",
    "9" => "Sep",
    "10" => "Oct",
    "11" => "Nov",
    "12" => "Dec"
  }

  defp month_desc(month), do: "in #{Map.get(@month_names, month, month)}"

  @weekday_names %{
    "0" => "Sunday",
    "1" => "Monday",
    "2" => "Tuesday",
    "3" => "Wednesday",
    "4" => "Thursday",
    "5" => "Friday",
    "6" => "Saturday",
    "7" => "Sunday"
  }

  defp weekday_desc("1-5"), do: "on weekdays"
  defp weekday_desc("0,6"), do: "on weekends"
  defp weekday_desc("6,0"), do: "on weekends"

  defp weekday_desc(weekday) do
    case Map.get(@weekday_names, weekday) do
      nil -> "on weekday #{weekday}"
      name -> "on #{name}"
    end
  end

  defp cron_field_desc(label, value), do: "#{label}=#{value}"

  defp safe_int(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp group_order("Minutes"), do: 0
  defp group_order("Hours"), do: 1
  defp group_order("Daily"), do: 2
  defp group_order("Weekly"), do: 3
  defp group_order("Monthly"), do: 4
  defp group_order(_), do: 5
end
