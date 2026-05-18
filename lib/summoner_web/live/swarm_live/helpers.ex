defmodule SummonerWeb.SwarmLive.Helpers do
  @moduledoc """
  Shared helpers for swarm (party) LiveViews.
  """

  @doc "Human-readable label for a swarm mode."
  def mode_label(:round_robin), do: "Round Robin"
  def mode_label(:relay), do: "Relay"
  def mode_label(:directed), do: "Directed"
  def mode_label(mode), do: mode

  @doc "CSS classes for the mode badge."
  def mode_badge_class(:round_robin),
    do: "badge badge-sm gap-1 bg-info/10 text-info border-info/30"

  def mode_badge_class(:relay),
    do: "badge badge-sm gap-1 bg-warning/10 text-warning border-warning/30"

  def mode_badge_class(:directed),
    do: "badge badge-sm gap-1 bg-secondary/10 text-secondary border-secondary/30"

  def mode_badge_class(_), do: "badge badge-sm badge-outline gap-1"

  @doc "Heroicon class for the mode."
  def mode_icon(:round_robin), do: "hero-arrow-path-rounded-square size-3"
  def mode_icon(:relay), do: "hero-link size-3"
  def mode_icon(:directed), do: "hero-bolt size-3"
  def mode_icon(_), do: ""

  @doc "Tooltip description for a swarm mode."
  def mode_description(:round_robin), do: "Summons take turns in fixed order"
  def mode_description(:relay), do: "Summons hand off via @callname relay"
  def mode_description(:directed), do: "A coordinator summon decides who speaks next"
  def mode_description(_), do: ""
end
