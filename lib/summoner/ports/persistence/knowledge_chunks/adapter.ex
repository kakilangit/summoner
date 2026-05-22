defmodule Summoner.Ports.Persistence.KnowledgeChunks.Adapter do
  @moduledoc "Behaviour for knowledge chunk persistence operations."

  @callback bulk_insert([map()]) :: {integer(), nil | [struct()]}
  @callback cosine_search([String.t()], list(), keyword()) :: [struct()]
  @callback delete_by_document(String.t(), String.t()) :: {integer(), nil}
  @callback delete_by_knowledge_base(String.t()) :: {integer(), nil}
  @callback count_by_knowledge_base(String.t()) :: integer()
  @callback list_by_document(String.t(), String.t(), keyword()) :: [struct()]
  @callback list_chunks_paginated(String.t(), keyword()) :: struct()
end
