defmodule Summoner.Adapters.Persistence.KnowledgeChunks do
  @moduledoc """
  Persistence adapter for knowledge chunks.

  Implements bulk insert, vector similarity search, and document-level
  operations for the RAG knowledge chunk system.
  """

  import Ecto.Query, warn: false

  alias Summoner.Domain.Schemas.KnowledgeChunk
  alias Summoner.Ports.Persistence.Pagination
  alias Summoner.Repo

  @behaviour Summoner.Ports.Persistence.KnowledgeChunks.Adapter

  @doc "Inserts multiple chunks at once, skipping conflicts."
  @impl true
  def bulk_insert(chunks) do
    Repo.insert_all(KnowledgeChunk, chunks, on_conflict: :nothing)
  end

  @doc "Searches chunks by cosine similarity across multiple knowledge bases."
  @impl true
  def cosine_search(kb_ids, embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    threshold = Keyword.get(opts, :threshold, 0.7)

    KnowledgeChunk
    |> where([c], c.knowledge_base_id in ^kb_ids)
    |> where([c], not is_nil(c.embedding))
    |> where([c], fragment("1 - (embedding <=> ?) >= ?", ^embedding, ^threshold))
    |> order_by([c], fragment("embedding <=> ?", ^embedding))
    |> limit(^limit)
    |> select_merge([c], %{similarity: fragment("1 - (embedding <=> ?)", ^embedding)})
    |> Repo.all()
  end

  @doc "Deletes all chunks for a document within a knowledge base."
  @impl true
  def delete_by_document(knowledge_base_id, document_name) do
    KnowledgeChunk
    |> where([c], c.knowledge_base_id == ^knowledge_base_id and c.document_name == ^document_name)
    |> Repo.delete_all()
  end

  @doc "Deletes all chunks for a knowledge base."
  @impl true
  def delete_by_knowledge_base(knowledge_base_id) do
    KnowledgeChunk
    |> where([c], c.knowledge_base_id == ^knowledge_base_id)
    |> Repo.delete_all()
  end

  @doc "Counts chunks for a knowledge base."
  @impl true
  def count_by_knowledge_base(knowledge_base_id) do
    KnowledgeChunk
    |> where([c], c.knowledge_base_id == ^knowledge_base_id)
    |> Repo.aggregate(:count)
  end

  @doc "Lists chunks for a document within a knowledge base."
  @impl true
  def list_by_document(knowledge_base_id, document_name, opts \\ []) do
    limit = Keyword.get(opts, :limit)

    KnowledgeChunk
    |> where([c], c.knowledge_base_id == ^knowledge_base_id and c.document_name == ^document_name)
    |> order_by([c], asc: c.inserted_at)
    |> maybe_limit(limit)
    |> Repo.all()
  end

  @doc "Lists chunks for a knowledge base with pagination."
  @impl true
  def list_chunks_paginated(knowledge_base_id, opts \\ []) do
    KnowledgeChunk
    |> where([c], c.knowledge_base_id == ^knowledge_base_id)
    |> Pagination.paginate(opts)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)
end
