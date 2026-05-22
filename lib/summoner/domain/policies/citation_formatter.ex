defmodule Summoner.Domain.Policies.CitationFormatter do
  @moduledoc """
  Formats retrieved knowledge chunks with citation markers.

  Pure function — no I/O. Used by the RAG retrieval pipeline to
  annotate chunks before injecting into agent context.
  """

  @doc """
  Formats chunks with citation markers for LLM consumption.

  Each chunk is annotated with source document and metadata:
  `[Source: document_name, page: N]` or `[Source: document_name]`.

  Returns formatted text ready for prompt injection.
  """
  def format_chunks(chunks) when is_list(chunks) do
    chunks
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {chunk, idx} ->
      citation = build_citation(chunk, idx)
      "#{citation}\n#{chunk.content}"
    end)
  end

  @doc """
  Extracts citation references from LLM response text.

  Finds patterns like [1], [Source: file.pdf], etc. and returns
  a list of `{index, document_name}` tuples.
  """
  def extract_citations(text) when is_binary(text) do
    ~r/\[(\d+)\]/
    |> Regex.scan(text)
    |> Enum.map(fn [_, idx] -> String.to_integer(idx) end)
    |> Enum.uniq()
  end

  defp build_citation(chunk, index) do
    doc = chunk.document_name
    page = get_in(chunk.metadata, ["page_number"]) || get_in(chunk.metadata, [:page_number])

    base = "[#{index}] [Source: #{doc}"

    if page do
      base <> ", page: #{page}]"
    else
      base <> "]"
    end
  end
end
