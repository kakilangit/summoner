defmodule Summoner.Services.RAG do
  @moduledoc """
  RAG retrieval service.

  Coordinates knowledge base lookup, embedding, cosine search,
  and citation formatting for agent context injection.
  """

  alias Summoner.Domain.Policies.CitationFormatter
  alias Summoner.Ports.Persistence.KnowledgeBases
  alias Summoner.Ports.Persistence.KnowledgeChunks
  alias Summoner.Services.Embedding

  @doc """
  Searches knowledge bases linked to an agent.

  Embeds the query, searches linked KBs by cosine similarity,
  returns formatted chunks with citations.
  """
  def search(agent_id, workspace_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    threshold = Keyword.get(opts, :threshold, 0.7)

    kb_ids =
      agent_id
      |> KnowledgeBases.list_knowledge_bases_for_agent()
      |> Enum.filter(&(&1.status == :ready))
      |> Enum.map(& &1.id)

    if kb_ids == [] do
      {:ok, []}
    else
      case Embedding.embed(workspace_id, query) do
        {:ok, embedding} ->
          chunks =
            KnowledgeChunks.cosine_search(kb_ids, embedding, limit: limit, threshold: threshold)

          {:ok, chunks}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Formats retrieved chunks with citations for prompt injection."
  def format_for_prompt(chunks) when chunks == [], do: nil

  def format_for_prompt(chunks) do
    formatted = CitationFormatter.format_chunks(chunks)

    """
    ## Relevant Knowledge

    The following excerpts are retrieved from linked knowledge bases. Cite sources using [N] markers when using this information.

    #{formatted}
    """
  end

  @doc "Triggers ingestion of a document into a knowledge base."
  def ingest_document(workspace_id, knowledge_base_id, filename, content_type) do
    %{
      workspace_id: workspace_id,
      knowledge_base_id: knowledge_base_id,
      filename: filename,
      content_type: content_type
    }
    |> Summoner.Adapters.Workers.RAG.IngestionWorker.new()
    |> Oban.insert()
  end

  @doc "Triggers re-indexing of a single document."
  def reindex_document(workspace_id, knowledge_base_id, filename, content_type) do
    %{
      workspace_id: workspace_id,
      knowledge_base_id: knowledge_base_id,
      mode: "incremental",
      filename: filename,
      content_type: content_type
    }
    |> Summoner.Adapters.Workers.RAG.ReindexWorker.new()
    |> Oban.insert()
  end

  @doc "Triggers full re-indexing of all documents in a knowledge base."
  def reindex_all(workspace_id, knowledge_base_id) do
    %{
      workspace_id: workspace_id,
      knowledge_base_id: knowledge_base_id,
      mode: "full"
    }
    |> Summoner.Adapters.Workers.RAG.ReindexWorker.new()
    |> Oban.insert()
  end

  @doc """
  Checks if a document has changed by comparing SHA-256 hashes.

  Returns `:changed`, `:unchanged`, or `:new`.
  """
  def check_document_change(kb, filename, binary) do
    current_hash = :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
    stored_hash = get_in(kb.file_hashes || %{}, [filename])

    cond do
      is_nil(stored_hash) -> :new
      stored_hash == current_hash -> :unchanged
      true -> :changed
    end
  end
end
