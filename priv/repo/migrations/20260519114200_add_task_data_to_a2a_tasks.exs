defmodule Summoner.Repo.Migrations.AddTaskDataToA2aTasks do
  use Ecto.Migration

  def change do
    alter table(:a2a_tasks) do
      add :task_data, :map
    end
  end
end
