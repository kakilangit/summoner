defmodule Summoner.Services.Embedding do
  @moduledoc "Shared embedding service for memory and RAG systems."

  alias Summoner.Ports.Persistence.Providers
  alias Summoner.Services.Inference.Gateway

  @doc """
  Embeds text using the workspace's configured embedding provider.
  Returns {:ok, vector} or {:error, reason}.

  Falls back to the first provider with embedding support if no
  explicit embedding provider is configured.
  """
  @spec embed(String.t(), String.t()) :: {:ok, list(float())} | {:error, term()}
  def embed(workspace_id, text) do
    with {:ok, provider, model} <- Providers.find_embedding_provider(workspace_id) do
      Gateway.embed(provider, model, text)
    end
  end

  @doc "Embeds a batch of texts. Returns {:ok, [vector]} or {:error, reason}."
  @spec embed_batch(String.t(), [String.t()]) :: {:ok, [list(float())]} | {:error, term()}
  def embed_batch(workspace_id, texts) do
    results = Enum.map(texts, fn text -> embed(workspace_id, text) end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, vec} -> vec end)}
      error -> error
    end
  end
end
