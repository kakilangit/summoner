defmodule Summoner.Ports.Persistence.Skills do
  @moduledoc "Port for skills persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :skills],
             Summoner.Adapters.Persistence.Skills
           )

  # CRUD
  defdelegate create_skill(scope, attrs), to: @adapter
  defdelegate list_skills(scope, workspace_id, tenant_id), to: @adapter
  defdelegate list_skills_paginated(scope, workspace_id, tenant_id), to: @adapter
  defdelegate list_skills_paginated(scope, workspace_id, tenant_id, opts), to: @adapter
  defdelegate get_skill!(scope, workspace_id, tenant_id, skill_id), to: @adapter
  defdelegate update_skill(scope, skill, attrs), to: @adapter
  defdelegate delete_skill(scope, skill), to: @adapter
  defdelegate change_skill(skill), to: @adapter
  defdelegate change_skill(skill, attrs), to: @adapter

  # Internal API
  defdelegate list_equipped_skills_internal(agent_id), to: @adapter

  # Equip / Unequip
  defdelegate equip_skill(scope, attrs), to: @adapter
  defdelegate unequip_skill(scope, agent_id, skill_id), to: @adapter
  defdelegate list_equipped_skills(scope, agent_id), to: @adapter
  defdelegate list_available_skills(scope, workspace_id, tenant_id, agent_id), to: @adapter

  # Embedding & Similarity Search
  defdelegate update_embedding(skill, embedding), to: @adapter
  defdelegate find_relevant_skills(agent_id, query_embedding), to: @adapter
  defdelegate find_relevant_skills(agent_id, query_embedding, opts), to: @adapter

  # Tenant-scoped
  defdelegate list_tenant_skills(tenant_id), to: @adapter
  defdelegate list_tenant_skills_paginated(tenant_id), to: @adapter
  defdelegate list_tenant_skills_paginated(tenant_id, opts), to: @adapter
  defdelegate get_tenant_skill!(tenant_id, id), to: @adapter
end
