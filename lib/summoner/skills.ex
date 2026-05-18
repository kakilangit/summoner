defmodule Summoner.Skills do
  @moduledoc """
  The Skills context (Spellbook).

  Manages workspace-scoped and tenant-scoped knowledge documents that
  can be equipped to agents. Skills may have vector embeddings for
  semantic similarity search via pgvector.
  """

  import Ecto.Query, warn: false

  alias Summoner.Pagination
  alias Summoner.Repo
  alias Summoner.Skills.{AgentSkill, Skill}

  # -------------------------------------------------------------------
  # CRUD
  # -------------------------------------------------------------------

  @doc """
  Creates a skill in a workspace or tenant.
  """
  def create_skill(%{user: _user}, attrs) do
    %Skill{}
    |> Skill.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists all skills for a workspace and its tenant.
  """
  def list_skills(%{user: _user}, workspace_id, tenant_id) do
    Skill
    |> where_scope(workspace_id, tenant_id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Lists skills for a workspace and its tenant with pagination.
  """
  def list_skills_paginated(%{user: _user}, workspace_id, tenant_id, opts \\ []) do
    Skill
    |> where_scope(workspace_id, tenant_id)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a skill by ID, scoped to workspace or tenant.
  """
  def get_skill!(%{user: _user}, workspace_id, tenant_id, skill_id) do
    Skill
    |> where_scope(workspace_id, tenant_id)
    |> Repo.get!(skill_id)
  end

  @doc """
  Updates a skill.
  """
  def update_skill(%{user: _user}, %Skill{} = skill, attrs) do
    skill
    |> Skill.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a skill.

  Returns error if agents still have this skill equipped.
  """
  def delete_skill(%{user: _user}, %Skill{} = skill) do
    skill
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.foreign_key_constraint(:agent_skills,
      name: :agent_skills_skill_id_fkey,
      message: "skill is still equipped by one or more familiars"
    )
    |> Repo.delete()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking skill changes.
  """
  def change_skill(%Skill{} = skill, attrs \\ %{}) do
    Skill.changeset(skill, attrs)
  end

  # -------------------------------------------------------------------
  # Internal API (for infrastructure use)
  # -------------------------------------------------------------------

  @doc """
  Lists equipped skills for an agent without scope.

  Intended for infrastructure use (e.g. Agent GenServer).
  """
  def list_equipped_skills_internal(agent_id) do
    AgentSkill
    |> where([as], as.agent_id == ^agent_id)
    |> preload(:skill)
    |> Repo.all()
    |> Enum.map(& &1.skill)
  end

  # -------------------------------------------------------------------
  # Equip / Unequip
  # -------------------------------------------------------------------

  @doc """
  Equips a skill to an agent.
  """
  def equip_skill(%{user: _user}, attrs) do
    %AgentSkill{}
    |> AgentSkill.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Unequips a skill from an agent.
  """
  def unequip_skill(%{user: _user}, agent_id, skill_id) do
    case Repo.get_by(AgentSkill, agent_id: agent_id, skill_id: skill_id) do
      nil -> {:error, :not_found}
      link -> Repo.delete(link)
    end
  end

  @doc """
  Lists all skills equipped to an agent.
  """
  def list_equipped_skills(%{user: _user}, agent_id) do
    AgentSkill
    |> where([as], as.agent_id == ^agent_id)
    |> preload(:skill)
    |> Repo.all()
    |> Enum.map(& &1.skill)
  end

  @doc """
  Lists skill IDs not yet equipped to an agent (for equip UI).
  """
  def list_available_skills(%{user: _user}, workspace_id, tenant_id, agent_id) do
    equipped_ids =
      AgentSkill
      |> where([as], as.agent_id == ^agent_id)
      |> select([as], as.skill_id)

    Skill
    |> where_scope(workspace_id, tenant_id)
    |> where([s], s.id not in subquery(equipped_ids))
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Embedding & Similarity Search
  # -------------------------------------------------------------------

  @doc """
  Updates the embedding vector for a skill.
  """
  def update_embedding(%Skill{} = skill, embedding) when is_list(embedding) do
    skill
    |> Ecto.Changeset.change(embedding: embedding)
    |> Repo.update()
  end

  @doc """
  Finds skills similar to the given query embedding using cosine distance.

  Returns skills ordered by similarity (most similar first), limited to `limit`.
  Only returns skills that are equipped to the given agent.
  """
  def find_relevant_skills(agent_id, query_embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    max_distance = Keyword.get(opts, :max_distance, 0.5)

    equipped_skill_ids =
      AgentSkill
      |> where([as], as.agent_id == ^agent_id)
      |> select([as], as.skill_id)

    Skill
    |> where([s], s.id in subquery(equipped_skill_ids))
    |> where([s], not is_nil(s.embedding))
    |> where(
      [s],
      fragment("? <=> ?::vector", s.embedding, ^Pgvector.new(query_embedding)) <= ^max_distance
    )
    |> order_by(
      [s],
      asc: fragment("? <=> ?::vector", s.embedding, ^Pgvector.new(query_embedding))
    )
    |> limit(^limit)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Tenant-scoped operations
  # -------------------------------------------------------------------

  @doc """
  Lists skills scoped to a tenant only.
  """
  def list_tenant_skills(tenant_id) do
    Skill
    |> where([s], s.tenant_id == ^tenant_id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Lists tenant-scoped skills with pagination.
  """
  def list_tenant_skills_paginated(tenant_id, opts \\ []) do
    Skill
    |> where([s], s.tenant_id == ^tenant_id)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a tenant-scoped skill by ID.
  """
  def get_tenant_skill!(tenant_id, id) do
    Skill
    |> where([s], s.tenant_id == ^tenant_id)
    |> Repo.get!(id)
  end

  defp where_scope(query, workspace_id, tenant_id) do
    where(query, [s], s.workspace_id == ^workspace_id or s.tenant_id == ^tenant_id)
  end
end
