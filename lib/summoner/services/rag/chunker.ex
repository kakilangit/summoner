defmodule Summoner.Services.RAG.Chunker do
  @moduledoc """
  Text chunking strategies for RAG ingestion.

  Splits document text into overlapping chunks suitable for
  embedding and retrieval. All functions are pure — no I/O.
  """

  @doc """
  Chunks text using the specified strategy.

  Returns a list of `%{content: String.t(), metadata: map()}`.
  """
  def chunk(text, strategy, opts \\ [])

  def chunk(text, :fixed, opts) do
    size = Keyword.get(opts, :chunk_size, 512)
    overlap = Keyword.get(opts, :chunk_overlap, 64)
    fixed_size(text, size, overlap)
  end

  def chunk(text, :paragraph, _opts) do
    paragraph(text)
  end

  def chunk(text, :semantic, opts) do
    size = Keyword.get(opts, :chunk_size, 512)
    overlap = Keyword.get(opts, :chunk_overlap, 64)
    semantic(text, size, overlap)
  end

  @doc "Fixed-size chunking with overlap. Respects sentence boundaries."
  def fixed_size(text, size, overlap) when size > 0 and overlap >= 0 and overlap < size do
    sentences = split_sentences(text)

    sentences
    |> build_chunks(size, overlap)
    |> Enum.with_index()
    |> Enum.map(fn {content, idx} ->
      %{content: content, metadata: %{chunk_index: idx, strategy: "fixed"}}
    end)
  end

  @doc "Paragraph-based chunking. Splits on double newlines, merges short paragraphs."
  def paragraph(text) do
    min_size = 100

    text
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> merge_short(min_size)
    |> Enum.with_index()
    |> Enum.map(fn {content, idx} ->
      %{content: content, metadata: %{chunk_index: idx, strategy: "paragraph"}}
    end)
  end

  @doc "Semantic chunking. Groups sentences, splitting at natural boundaries."
  def semantic(text, size, overlap) do
    sentences = split_sentences(text)

    sentences
    |> build_chunks(size, overlap)
    |> Enum.with_index()
    |> Enum.map(fn {content, idx} ->
      %{content: content, metadata: %{chunk_index: idx, strategy: "semantic"}}
    end)
  end

  defp split_sentences(text) do
    text
    |> String.split(~r/(?<=[.!?])\s+/, trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  defp build_chunks(sentences, size, overlap) do
    build_chunks(sentences, size, overlap, [], [])
  end

  defp build_chunks([], _size, _overlap, current, acc) do
    case current do
      [] -> Enum.reverse(acc)
      _ -> Enum.reverse([Enum.join(Enum.reverse(current), " ") | acc])
    end
  end

  defp build_chunks([sentence | rest], size, overlap, current, acc) do
    current_text = current |> Enum.reverse() |> Enum.join(" ")
    new_length = String.length(current_text) + String.length(sentence) + 1

    if current != [] and new_length > size do
      chunk = current_text
      overlap_sentences = take_overlap(current, overlap)
      build_chunks([sentence | rest], size, overlap, overlap_sentences, [chunk | acc])
    else
      build_chunks(rest, size, overlap, [sentence | current], acc)
    end
  end

  defp take_overlap(_sentences, overlap) when overlap <= 0, do: []

  defp take_overlap(sentences, overlap) do
    sentences
    |> Enum.reduce_while({[], 0}, fn sentence, {kept, len} ->
      new_len = len + String.length(sentence) + 1

      if new_len > overlap do
        {:halt, {kept, new_len}}
      else
        {:cont, {[sentence | kept], new_len}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp merge_short(paragraphs, min_size) do
    paragraphs
    |> Enum.reduce([], fn para, acc ->
      case acc do
        [last | rest] when byte_size(last) < min_size ->
          [last <> "\n\n" <> para | rest]

        _ ->
          [para | acc]
      end
    end)
    |> Enum.reverse()
  end
end
