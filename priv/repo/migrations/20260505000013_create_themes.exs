defmodule Summoner.Repo.Migrations.CreateThemes do
  use Ecto.Migration

  def change do
    create table(:themes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :display_name, :string, null: false
      add :color_scheme, :string, null: false
      add :author, :string
      add :version, :string
      add :tokens, :map, null: false
      add :is_builtin, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:themes, [:name])
  end
end
