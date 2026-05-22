defmodule Summoner.Ports.Persistence.KnowledgeChunks do
  @moduledoc "Port for knowledge chunk persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :knowledge_chunks],
             Summoner.Adapters.Persistence.KnowledgeChunks
           )

  defdelegate bulk_insert(chunks), to: @adapter
  defdelegate cosine_search(kb_ids, embedding, opts \\ []), to: @adapter
  defdelegate delete_by_document(knowledge_base_id, document_name), to: @adapter
  defdelegate delete_by_knowledge_base(knowledge_base_id), to: @adapter
  defdelegate count_by_knowledge_base(knowledge_base_id), to: @adapter
  defdelegate list_by_document(knowledge_base_id, document_name, opts \\ []), to: @adapter
  defdelegate list_chunks_paginated(knowledge_base_id, opts \\ []), to: @adapter
end
