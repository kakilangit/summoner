defmodule Summoner.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime_usec
      add :role, :string, null: false, default: "user"
      add :theme, :string, default: "elixir-dark"
      add :disabled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])
  end
end
