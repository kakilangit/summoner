defmodule Summoner.Repo.Migrations.RemovePluginContainerActiveInstalls do
  use Ecto.Migration

  def change do
    alter table(:plugin_containers) do
      remove :active_installs, :integer, default: 0
    end
  end
end
