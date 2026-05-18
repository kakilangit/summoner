defmodule Summoner.Factory do
  @moduledoc """
  Test factory for building and inserting test data.

  ## Usage

      import Summoner.Factory

      # Build a struct without persisting
      workspace = build(:workspace)

      # Build with overrides
      workspace = build(:workspace, name: "Custom Name")

      # Insert into the database
      workspace = insert(:workspace)
      workspace = insert(:workspace, name: "Custom Name")
  """

  def build(:workspace) do
    %{
      name: "Workspace #{System.unique_integer([:positive])}"
    }
  end

  def build(factory, attrs) do
    factory
    |> build()
    |> Map.merge(Map.new(attrs))
  end

  def insert(factory, attrs \\ []) do
    factory
    |> build(attrs)
    |> then(&apply_insert(factory, &1))
  end

  defp apply_insert(_factory, attrs) do
    # Placeholder — concrete inserts are added as schemas are created.
    # Each context should provide its own create function; the factory
    # calls that function rather than inserting raw maps.
    {:ok, attrs}
  end
end
