defmodule Summoner.Inference do
  @moduledoc """
  Bridge between Summoner domain and the Arcanum inference library.

  Enriches provider structs with decrypted API keys before delegating
  to `Arcanum` modules.
  """

  alias Summoner.Providers.Provider

  @doc """
  Returns the adapter module for the given provider.
  Delegates to `Arcanum.adapter_for/1`.
  """
  defdelegate adapter_for(provider), to: Arcanum

  @doc """
  Enriches a `%Provider{}` struct with a decrypted `:api_key` field
  so Arcanum adapters can read it via `Map.get(provider, :api_key)`.
  """
  @spec enrich_provider(map()) :: map()
  def enrich_provider(%Provider{} = provider) do
    Map.put(provider, :api_key, Provider.api_key(provider))
  end

  def enrich_provider(provider), do: provider
end
