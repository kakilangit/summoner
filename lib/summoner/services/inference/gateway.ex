defmodule Summoner.Services.Inference.Gateway do
  @moduledoc """
  Bridge to `Arcanum.Gateway`.

  Enriches provider with decrypted API key before delegating.
  For grimoire providers, resolves container URL dynamically.
  """

  alias Arcanum.{Intent, Response}
  alias Summoner.Services.Inference

  @spec chat(map(), Intent.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def chat(provider, %Intent{} = intent, opts \\ []) do
    with {:ok, provider} <- enrich(provider) do
      Arcanum.Gateway.chat(provider, intent, opts)
    end
  end

  @spec stream(map(), Intent.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(provider, %Intent{} = intent, opts \\ []) do
    with {:ok, provider} <- enrich(provider) do
      Arcanum.Gateway.stream(provider, intent, opts)
    end
  end

  @spec list_models(map()) :: {:ok, [String.t()]} | {:error, term()}
  def list_models(provider) do
    with {:ok, provider} <- enrich(provider) do
      Arcanum.Gateway.list_models(provider)
    end
  end

  @spec embed(map(), String.t(), String.t()) :: {:ok, [float()]} | {:error, term()}
  def embed(provider, model, input) do
    with {:ok, provider} <- enrich(provider) do
      Arcanum.Gateway.embed(provider, model, input)
    end
  end

  @spec generate_image(map(), Intent.t(), keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def generate_image(provider, %Intent{} = intent, opts \\ []) do
    with {:ok, provider} <- enrich(provider) do
      Arcanum.Gateway.generate_image(provider, intent, opts)
    end
  end

  @spec generate_video(map(), Intent.t(), keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def generate_video(provider, %Intent{} = intent, opts \\ []) do
    with {:ok, provider} <- enrich(provider) do
      Arcanum.Gateway.generate_video(provider, intent, opts)
    end
  end

  defp enrich(provider) do
    enriched = Inference.enrich_provider(provider)

    if Map.get(enriched, :api_format) in [:grimoire, "grimoire"] and is_nil(enriched.base_url) do
      {:error, :container_not_available}
    else
      {:ok, enriched}
    end
  end
end
