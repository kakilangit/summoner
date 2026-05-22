defmodule Summoner.Adapters.Workers.RAG.IngestionWorker do
  @moduledoc """
  Oban worker for RAG document ingestion.

  Orchestrates the full pipeline: read file → parse → chunk →
  embed → bulk insert chunks → update knowledge base status.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Summoner.Ports.DocumentParser
  alias Summoner.Ports.Persistence.KnowledgeBases
  alias Summoner.Ports.Persistence.KnowledgeChunks
  alias Summoner.Services.Embedding
  alias Summoner.Services.RAG.Chunker

  @batch_size 50

  @impl true
  def perform(%Oban.Job{
        args: %{
          "workspace_id" => workspace_id,
          "knowledge_base_id" => kb_id,
          "filename" => filename,
          "content_type" => content_type
        }
      }) do
    kb = KnowledgeBases.get_knowledge_base!(workspace_id, kb_id)

    KnowledgeBases.update_status(kb, %{status: :indexing})

    case ingest(kb, workspace_id, filename, content_type) do
      :ok ->
        kb = KnowledgeBases.get_knowledge_base!(workspace_id, kb_id)
        chunk_count = KnowledgeChunks.count_by_knowledge_base(kb_id)
        Logger.info("Ingested #{filename} into #{kb.name}: #{chunk_count} chunks")
        KnowledgeBases.update_status(kb, %{status: :ready, error_message: nil})
        :ok

      {:error, reason} ->
        Logger.error("Ingestion failed for #{filename}: #{inspect(reason)}")
        kb = KnowledgeBases.get_knowledge_base!(workspace_id, kb_id)
        KnowledgeBases.update_status(kb, %{status: :error, error_message: inspect(reason)})
        {:error, reason}
    end
  end

  defp ingest(kb, workspace_id, filename, content_type) do
    upload_dir =
      Path.join([Application.app_dir(:summoner, "priv"), "uploads", "knowledge_bases", kb.id])

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
end
