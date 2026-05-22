defmodule Summoner.Adapters.Workers.RAG.ReindexWorker do
  @moduledoc """
  Oban worker for RAG knowledge base re-indexing.

  Supports incremental (single document) and full (all documents)
  re-indexing. Deletes old chunks before re-ingesting.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Summoner.Ports.DocumentParser
  alias Summoner.Ports.Persistence.KnowledgeBases
  alias Summoner.Ports.Persistence.KnowledgeChunks
  alias Summoner.Services.Embedding
  alias Summoner.Services.RAG.Chunker

  @batch_size 50

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "workspace_id" => workspace_id,
            "knowledge_base_id" => kb_id,
            "mode" => mode
          } = args
      }) do
    kb = KnowledgeBases.get_knowledge_base!(workspace_id, kb_id)
    KnowledgeBases.update_status(kb, %{status: :indexing})

    result =
      case mode do
        "incremental" ->
          filename = args["filename"]
          content_type = args["content_type"]
          reindex_document(kb, workspace_id, filename, content_type)

        "full" ->
          reindex_all(kb, workspace_id)
      end

    kb = KnowledgeBases.get_knowledge_base!(workspace_id, kb_id)

    case result do
      :ok ->
        KnowledgeBases.update_status(kb, %{status: :ready, error_message: nil})
        :ok

      {:error, reason} ->
        Logger.error("Re-index failed for #{kb.name}: #{inspect(reason)}")
        KnowledgeBases.update_status(kb, %{status: :error, error_message: inspect(reason)})
        {:error, reason}
    end
  end

  defp reindex_document(kb, workspace_id, filename, content_type) do
    # Delete existing chunks for this document
    KnowledgeChunks.delete_by_document(kb.id, filename)

    # Re-ingest
    upload_dir = upload_path(kb)
    file_path = Path.join(upload_dir, filename)

    with {:ok, binary} <- File.read(file_path),
         {:ok, parsed} <- DocumentParser.parse(binary, content_type),
         chunks <-
           Chunker.chunk(parsed.text, kb.chunk_strategy,
             chunk_size: kb.chunk_size,
             chunk_overlap: kb.chunk_overlap
           ),
         :ok <- embed_and_store(chunks, kb, workspace_id, filename, parsed.metadata) do
      :ok
    end
  end

  defp reindex_all(kb, workspace_id) do
    # Delete all chunks
    KnowledgeChunks.delete_by_knowledge_base(kb.id)

    upload_dir = upload_path(kb)

    if File.dir?(upload_dir) do
      upload_dir
      |> File.ls!()
      |> Enum.reduce_while(:ok, fn filename, :ok ->
        content_type = detect_content_type(filename)

        case reindex_document(kb, workspace_id, filename, content_type) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    else
      :ok
    end
  end

  defp embed_and_store(chunks, kb, workspace_id, filename, doc_metadata) do
    chunks
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce_while(:ok, fn batch, :ok ->
      texts = Enum.map(batch, & &1.content)

      case Embedding.embed_batch(workspace_id, texts) do
        {:ok, embeddings} ->
          now = DateTime.utc_now()

          rows =
            Enum.zip(batch, embeddings)
            |> Enum.map(fn {chunk, embedding} ->
              %{
                id: Nulid.Ecto.autogenerate(),
                content: chunk.content,
                embedding: embedding,
                metadata: Map.merge(chunk.metadata, doc_metadata),
                document_name: filename,
                knowledge_base_id: kb.id,
                workspace_id: workspace_id,
                inserted_at: now,
                updated_at: now
              }
            end)

          KnowledgeChunks.bulk_insert(rows)
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp upload_path(kb) do
    Path.join([Application.app_dir(:summoner, "priv"), "uploads", "knowledge_bases", kb.id])
  end

  defp detect_content_type(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".txt" -> "text/plain"
      ".md" -> "text/markdown"
      ".html" -> "text/html"
      ".htm" -> "text/html"
      ".pdf" -> "application/pdf"
      ".docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      _ -> "text/plain"
    end
  end
end
