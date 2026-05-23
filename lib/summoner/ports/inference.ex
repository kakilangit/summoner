defmodule Summoner.Services.Inference do
  @moduledoc """
  Bridge between Summoner domain and the Arcanum inference library.

  Enriches provider structs with decrypted API keys before delegating
  to `Arcanum` modules. For grimoire providers, resolves the container
  URL dynamically.
  """

  alias Summoner.Adapters.Workers.PluginContainerManager
  alias Summoner.Domain.Schemas.Provider
  alias Summoner.Services.Plugins.TrustVerifier

  @doc """
  Returns the adapter module for the given provider.
  Delegates to `Arcanum.adapter_for/1`.
  """
  defdelegate adapter_for(provider), to: Arcanum

  @doc """
  Enriches a `%Provider{}` struct with a decrypted `:api_key` field
  so Arcanum adapters can read it via `Map.get(provider, :api_key)`.

  For grimoire providers, resolves the container base_url and injects
  the plugin context.
  """
  @spec enrich_provider(map()) :: map()
  def enrich_provider(%Provider{api_format: :grimoire} = provider) do
    provider
    |> enrich_grimoire_base_url()
    |> enrich_grimoire_context()
  end

  def enrich_provider(%Provider{} = provider) do
    Map.put(provider, :api_key, Provider.api_key(provider))
  end

  def enrich_provider(provider), do: provider

  # -------------------------------------------------------------------
  # Grimoire enrichment
  # -------------------------------------------------------------------

  defp enrich_grimoire_base_url(
         %Provider{plugin_installation: %{digest: digest} = plugin} = provider
       ) do
    isolation =
      TrustVerifier.effective_isolation(plugin.trusted, get_in(plugin.manifest, ["isolation"]))

    tenant_id = if isolation == :tenant, do: plugin.workspace_id, else: nil

    case PluginContainerManager.get_container(digest, tenant_id) do
      {:ok, container} ->
        Map.put(provider, :base_url, "http://#{container.host}:#{container.port}")

      {:error, _reason} ->
        provider
    end
  end

  defp enrich_grimoire_base_url(provider), do: provider

  defp enrich_grimoire_context(%Provider{plugin_installation: plugin} = provider)
       when not is_nil(plugin) do
    context = %{
      workspace_id: provider.workspace_id,
      plugin_id: plugin.id,
      config: plugin.config || %{}
    }

    Map.put(provider, :grimoire_context, context)
  end

  defp enrich_grimoire_context(provider), do: provider
end
