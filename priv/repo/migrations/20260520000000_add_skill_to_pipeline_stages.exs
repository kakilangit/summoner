defmodule Summoner.Repo.Migrations.AddSkillToPipelineStages do
  use Ecto.Migration

  def change do
    alter table(:pipeline_stages) do
      add :skill, :string
    end
  end
end
