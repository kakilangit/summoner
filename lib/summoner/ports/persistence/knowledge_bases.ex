defmodule Summoner.Ports.Persistence.KnowledgeBases do
  @moduledoc "Port for knowledge base persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :knowledge_bases],
             Summoner.Adapters.Persistence.KnowledgeBases
           )

  defdelegate create_knowledge_base(workspace_id, attrs), to: @adapter
  defdelegate get_knowledge_base!(workspace_id, id), to: @adapter
  defdelegate get_knowledge_base(workspace_id, id), to: @adapter
  defdelegate list_knowledge_bases(workspace_id), to: @adapter
  defdelegate list_knowledge_bases_paginated(workspace_id, opts \\ []), to: @adapter
  defdelegate update_knowledge_base(kb, attrs), to: @adapter
  defdelegate update_status(kb, attrs), to: @adapter
  defdelegate delete_knowledge_base(kb), to: @adapter
  defdelegate link_agent(knowledge_base_id, agent_id), to: @adapter
  defdelegate unlink_agent(knowledge_base_id, agent_id), to: @adapter
  defdelegate list_linked_agents(knowledge_base_id), to: @adapter
  defdelegate list_knowledge_bases_for_agent(agent_id), to: @adapter
end
