defmodule SummonerWeb.API.V1.ProviderJSON do
  @moduledoc "JSON rendering for providers."

  def index(%{providers: providers}) do
    %{data: Enum.map(providers, &provider_data/1)}
  end

  def show(%{provider: provider}) do
    %{data: provider_data(provider)}
  end

  defp provider_data(p) do
    %{
      id: p.id,
      name: p.name,
      kind: p.kind,
      api_format: p.api_format,
      type: p.type,
      base_url: p.base_url,
      status: p.status,
      cached_models: p.cached_models,
      workspace_id: p.workspace_id,
      tenant_id: p.tenant_id,
      api_key_secret_id: p.api_key_secret_id,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at
    }
  end
end
