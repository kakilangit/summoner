defmodule Summoner.Repo.Migrations.CreateSkills do
  use Ecto.Migration

  def change do
    create table(:skills, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :content, :text, null: false
      add :embedding, :vector, size: 1536

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all)
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all)

      timestamps()
    end

    create constraint(:skills, :skills_scope_xor,
             check: "(tenant_id IS NOT NULL) != (workspace_id IS NOT NULL)"
           )

    create unique_index(:skills, [:workspace_id, :name], where: "workspace_id IS NOT NULL")
    create unique_index(:skills, [:tenant_id, :name], where: "tenant_id IS NOT NULL")
    create index(:skills, [:workspace_id])
    create index(:skills, [:tenant_id])
  end
end
