defmodule Summoner.Repo.Migrations.AddParallelExecutionFields do
  use Ecto.Migration

  def change do
    alter table(:local_agents) do
      add :max_tool_concurrency, :integer
    end

    alter table(:workspace_settings) do
      add :default_max_tool_concurrency, :integer, default: 5, null: false
    end
  end
end
