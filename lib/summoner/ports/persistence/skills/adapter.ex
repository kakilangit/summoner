defmodule Summoner.Ports.Persistence.Skills.Adapter do
  @moduledoc "Behaviour for skills persistence operations."

  # CRUD
  @callback create_skill(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_skills(map(), String.t(), String.t()) :: [struct()]
  @callback list_skills_paginated(map(), String.t(), String.t()) :: struct()
  @callback list_skills_paginated(map(), String.t(), String.t(), keyword()) :: struct()
  @callback get_skill!(map(), String.t(), String.t(), String.t()) :: struct()
  @callback update_skill(map(), struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_skill(map(), struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback change_skill(struct()) :: Ecto.Changeset.t()
  @callback change_skill(struct(), map()) :: Ecto.Changeset.t()

  # Internal API
  @callback list_equipped_skills_internal(String.t()) :: [struct()]

  # Equip / Unequip
  @callback equip_skill(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback unequip_skill(map(), String.t(), String.t()) ::
              {:ok, struct()} | {:error, :not_found}
  @callback list_equipped_skills(map(), String.t()) :: [struct()]
  @callback list_available_skills(map(), String.t(), String.t(), String.t()) :: [struct()]

  # Embedding & Similarity Search
  @callback update_embedding(struct(), list()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback find_relevant_skills(String.t(), list()) :: [struct()]
  @callback find_relevant_skills(String.t(), list(), keyword()) :: [struct()]

  # Tenant-scoped
  @callback list_tenant_skills(String.t()) :: [struct()]
  @callback list_tenant_skills_paginated(String.t()) :: struct()
  @callback list_tenant_skills_paginated(String.t(), keyword()) :: struct()
  @callback get_tenant_skill!(String.t(), String.t()) :: struct()
end
