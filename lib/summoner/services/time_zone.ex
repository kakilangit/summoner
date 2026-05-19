defmodule Summoner.Services.TimeZone do
  @moduledoc """
  Timezone conversion helpers.

  All timestamps are stored as UTC in the database. This module converts
  them to the configured local timezone for display purposes only.

  The local timezone is configured via:

      config :summoner, local_timezone: "Europe/Berlin"
  """

  @doc """
  Returns the configured local timezone identifier.

  Defaults to `"Europe/Berlin"` if not configured.
  """
  def local_timezone do
    Application.get_env(:summoner, :local_timezone, "Europe/Berlin")
  end

  @doc """
  Shifts a UTC datetime to the configured local timezone.

  Returns the original datetime unchanged if conversion fails.
  """
  def to_local(%DateTime{} = dt) do
    case DateTime.shift_zone(dt, local_timezone()) do
      {:ok, local} -> local
      {:error, _} -> dt
    end
  end

  def to_local(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> to_local()
  end

  def to_local(nil), do: nil

  @doc """
  Formats a UTC datetime for display in the local timezone.

  Uses the given `strftime` format string. Appends the timezone
  abbreviation by default.

  ## Options

  - `:format` — strftime pattern (default `"%Y-%m-%d %H:%M"`)
  - `:show_zone` — append timezone abbreviation (default `true`)
  """
  def format(dt, opts \\ [])

  def format(nil, _opts), do: ""

  def format(dt, opts) do
    pattern = Keyword.get(opts, :format, "%Y-%m-%d %H:%M")
    show_zone = Keyword.get(opts, :show_zone, true)

    local = to_local(dt)

    base = Calendar.strftime(local, pattern)

    if show_zone do
      zone = zone_abbr(local)
      "#{base} #{zone}"
    else
      base
    end
  end

  defp zone_abbr(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Z")
  end

  defp zone_abbr(_), do: "UTC"

  @doc """
  Formats a UTC datetime as a smart relative/absolute string for chat UIs.

  - Today: "14:32"
  - Yesterday: "Yesterday 14:32"
  - Within 7 days: "2 days ago 14:32"
  - Older than 7 days: "May 8, 14:32"
  """
  def format_chat_timestamp(nil), do: ""

  def format_chat_timestamp(dt) do
    local = to_local(dt)
    now = to_local(DateTime.utc_now())
    today = DateTime.to_date(now)
    msg_date = DateTime.to_date(local)
    days_ago = Date.diff(today, msg_date)
    time = Calendar.strftime(local, "%H:%M")

    cond do
      days_ago == 0 -> time
      days_ago == 1 -> "Yesterday #{time}"
      days_ago < 7 -> "#{days_ago} days ago #{time}"
      true -> Calendar.strftime(local, "%b %-d, %H:%M")
    end
  end
end
