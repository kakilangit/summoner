defmodule Summoner.Workers.PipelineScheduler do
  @moduledoc """
  Oban cron worker that checks for due scheduled pipelines.

  Runs every minute. For each pipeline with `trigger_type: :scheduled`,
  evaluates whether the cron expression matches the current minute and
  enqueues a `PipelineRunner` job if so.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Summoner.Pipelines
  alias Summoner.Workers.PipelineRunnerJob

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    Pipelines.list_scheduled_pipelines()
    |> Enum.filter(&cron_matches?(&1.cron_expression, now))
    |> Enum.each(&enqueue_run/1)

    :ok
  end

  defp enqueue_run(pipeline) do
    unless Pipelines.has_active_run?(pipeline.id) do
      %{
        pipeline_id: pipeline.id,
        workspace_id: pipeline.workspace_id,
        input: ""
      }
      |> PipelineRunnerJob.new()
      |> Oban.insert()
    end
  end

  @doc """
  Checks whether a 5-field cron expression matches the given datetime.

  Supports: `*`, specific values, comma-separated lists, ranges (`-`),
  and step values (`/`).
  """
  def cron_matches?(nil, _now), do: false

  def cron_matches?(expression, now) do
    case String.split(expression, ~r/\s+/, trim: true) do
      [minute, hour, day, month, weekday] ->
        field_matches?(minute, now.minute) &&
          field_matches?(hour, now.hour) &&
          field_matches?(day, now.day) &&
          field_matches?(month, now.month) &&
          field_matches?(weekday, Date.day_of_week(now) |> remap_weekday())

      _ ->
        false
    end
  end

  # Cron weekday: 0=Sunday, 1=Monday...6=Saturday
  # Elixir Date.day_of_week: 1=Monday...7=Sunday
  defp remap_weekday(7), do: 0
  defp remap_weekday(d), do: d

  defp field_matches?("*", _value), do: true

  defp field_matches?(field, value) do
    field
    |> String.split(",")
    |> Enum.any?(&part_matches?(&1, value))
  end

  defp part_matches?(part, value) do
    cond do
      String.contains?(part, "/") ->
        step_matches?(part, value)

      String.contains?(part, "-") ->
        range_matches?(part, value)

      true ->
        case Integer.parse(part) do
          {n, ""} -> n == value
          _ -> false
        end
    end
  end

  defp step_matches?(part, value) do
    case String.split(part, "/") do
      ["*", step_str] ->
        case Integer.parse(step_str) do
          {step, ""} when step > 0 -> rem(value, step) == 0
          _ -> false
        end

      [range_str, step_str] ->
        with {step, ""} <- Integer.parse(step_str),
             true <- step > 0,
             [lo_str, hi_str] <- String.split(range_str, "-"),
             {lo, ""} <- Integer.parse(lo_str),
             {hi, ""} <- Integer.parse(hi_str) do
          value >= lo && value <= hi && rem(value - lo, step) == 0
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp range_matches?(part, value) do
    case String.split(part, "-") do
      [lo_str, hi_str] ->
        with {lo, ""} <- Integer.parse(lo_str),
             {hi, ""} <- Integer.parse(hi_str) do
          value >= lo && value <= hi
        else
          _ -> false
        end

      _ ->
        false
    end
  end
end
