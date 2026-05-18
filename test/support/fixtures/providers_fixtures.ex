defmodule Summoner.ProvidersFixtures do
  @moduledoc """
  Test helpers for creating provider entities.
  """

  alias Summoner.Providers

  def unique_provider_name, do: "provider-#{System.unique_integer([:positive])}"

  def valid_provider_attributes(workspace_id, attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_provider_name(),
      kind: "ollama",
      api_format: :openai,
      type: :local,
      base_url: "http://localhost:11434",
      workspace_id: workspace_id
    })
  end

  def provider_fixture(scope, workspace_id, attrs \\ %{}) do
    {:ok, provider} =
      workspace_id
      |> valid_provider_attributes(attrs)
      |> then(&Providers.create_provider(scope, &1))

    provider
  end
end
