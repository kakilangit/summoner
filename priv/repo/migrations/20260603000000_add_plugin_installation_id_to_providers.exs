defmodule Summoner.Repo.Migrations.AddPluginInstallationIdToProviders do
  use Ecto.Migration

  def change do
    alter table(:providers) do
      add :plugin_installation_id,
          references(:plugin_installations, type: :binary_id, on_delete: :nilify_all)

      modify :base_url, :string, null: true, from: {:string, null: false}
    end

    create index(:providers, [:plugin_installation_id])
  end
end
