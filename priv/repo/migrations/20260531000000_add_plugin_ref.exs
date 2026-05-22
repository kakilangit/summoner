defmodule Summoner.Repo.Migrations.AddPluginRef do
  use Ecto.Migration

  def change do
    alter table(:plugin_installations) do
      add :ref, :string, size: 12
    end

    create index(:plugin_installations, [:workspace_id, :ref], unique: true)
  end
end
