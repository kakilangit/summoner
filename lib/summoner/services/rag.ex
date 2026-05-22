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
end
