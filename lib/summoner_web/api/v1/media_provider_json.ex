defmodule SummonerWeb.API.V1.MediaProviderJSON do
  @moduledoc "JSON rendering for media providers."

  import SummonerWeb.API.PaginationJSON

  def index(%{page: page}) do
    %{items: Enum.map(page.entries, &media_provider_data/1), meta: page_meta(page)}
  end

  def show(%{media_provider: provider}) do
    media_provider_data(provider)
  end

  defp media_provider_data(p) do
    %{
      id: p.id,
      name: p.name,
      default_image_model: p.default_image_model,
      default_video_model: p.default_video_model,
      max_concurrent_jobs: p.max_concurrent_jobs,
      config: p.config,
      workspace_id: p.workspace_id,
      tenant_id: p.tenant_id,
      provider_id: p.provider_id,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at
    }
  end
end
