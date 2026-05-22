defmodule Summoner.Domain.Schemas.PluginState do
  @moduledoc """
  Schema for plugin state (key-value store).

  Workspace-scoped: shared containers serve multiple workspaces
  but each workspace has its own state partition.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.{PluginInstallation, Workspace}

  schema "plugin_state" do
    field :key, :string
    field :value, :map

    belongs_to :workspace, Workspace
    belongs_to :plugin, PluginInstallation

    timestamps()
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:key, :value, :workspace_id, :plugin_id])
    |> validate_required([:key, :value, :workspace_id, :plugin_id])
    |> unique_constraint([:workspace_id, :plugin_id, :key])
  end
end
