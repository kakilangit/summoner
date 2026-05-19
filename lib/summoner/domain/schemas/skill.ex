defmodule Summoner.Domain.Schemas.Skill do
  @moduledoc """
  Schema for skills (knowledge documents).

  A skill contains instructional or reference content that can be
  equipped to agents. Skills may have vector embeddings for semantic
  similarity search.

  A skill belongs to exactly one of a workspace or a tenant (XOR).
  Tenant-scoped skills are shared across all workspaces in the tenant.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Tenant
  alias Summoner.Domain.Schemas.Workspace

  schema "skills" do
    field :name, :string
    field :content, :string
    field :embedding, Pgvector.Ecto.Vector

    belongs_to :workspace, Workspace
    belongs_to :tenant, Tenant

    has_many :agent_skills, Summoner.Domain.Schemas.AgentSkill
    has_many :agents, through: [:agent_skills, :agent]

    timestamps()
  end

  def changeset(skill, attrs) do
    skill
    |> cast(attrs, [:name, :content, :embedding, :workspace_id, :tenant_id])
    |> validate_required([:name, :content])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_scope()
    |> unique_constraint([:workspace_id, :name])
    |> unique_constraint([:tenant_id, :name])
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:tenant_id)
  end

  defp validate_scope(changeset) do
    tenant_id = get_field(changeset, :tenant_id)
    workspace_id = get_field(changeset, :workspace_id)

    cond do
      is_nil(tenant_id) and is_nil(workspace_id) ->
        add_error(changeset, :base, "must belong to either a tenant or a workspace")

      not is_nil(tenant_id) and not is_nil(workspace_id) ->
        add_error(changeset, :base, "cannot belong to both a tenant and a workspace")

      true ->
        changeset
    end
  end
end
