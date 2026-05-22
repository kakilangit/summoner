defmodule Summoner.Domain.Policies.MemoryDeduplication do
  @moduledoc """
  Pure deduplication check for agent memories.

  Compares memory content using normalized string similarity
  (Jaro-Winkler distance). Two memories are considered duplicates
  if their content similarity exceeds a threshold.
  """

  @default_threshold 0.9

  @doc """
  Returns true if two memory contents are considered duplicates.

  Uses Jaro-Winkler string similarity on downcased, trimmed content.
  """
  @spec duplicate?(String.t(), String.t(), keyword()) :: boolean()
  def duplicate?(content_a, content_b, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)

    normalized_a = normalize(content_a)
    normalized_b = normalize(content_b)

    normalized_a == normalized_b ||
      String.jaro_distance(normalized_a, normalized_b) >= threshold
  end

  defp normalize(text) do
    text
    |> String.trim()
    |> String.downcase()
  end
end
