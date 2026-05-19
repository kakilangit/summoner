defmodule Summoner.Adapters.Persistence.MediaProvidersFixtures do
  @moduledoc """
  Test helpers for creating media provider (Forge) entities.
  """

  alias Summoner.Adapters.Persistence.MediaProviders

  def valid_media_provider_attributes(workspace_id, attrs \\ %{}) do
    Enum.into(attrs, %{
      workspace_id: workspace_id,
      name: "Test Forge #{System.unique_integer([:positive])}",
      default_image_model: "gpt-image-1",
      max_concurrent_jobs: 3,
      config: %{}
    })
  end

  def media_provider_fixture(scope, workspace_id, attrs \\ %{}) do
    attrs = valid_media_provider_attributes(workspace_id, attrs)
    {:ok, provider} = MediaProviders.create_media_provider(scope, attrs)
    provider
  end
end
