defmodule SummonerWeb.API.V1.ProviderJSON do
  @moduledoc "JSON rendering for providers."

  import SummonerWeb.API.PaginationJSON

  def index(%{page: page}) do
    %{items: Enum.map(page.entries, &provider_data/1), meta: page_meta(page)}
  end

  def show(%{provider: provider}) do
    provider_data(provider)
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
