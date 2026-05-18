defmodule Summoner.Inference.Gateway do
  @moduledoc """
  Bridge to `Arcanum.Gateway`.

  Enriches provider with decrypted API key before delegating.
  """

  alias Arcanum.{Intent, Response}
  alias Summoner.Inference

  @spec chat(map(), Intent.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def chat(provider, %Intent{} = intent, opts \\ []) do
    Arcanum.Gateway.chat(Inference.enrich_provider(provider), intent, opts)
  end

  @spec stream(map(), Intent.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(provider, %Intent{} = intent, opts \\ []) do
    Arcanum.Gateway.stream(Inference.enrich_provider(provider), intent, opts)
  end

  @spec list_models(map()) :: {:ok, [String.t()]} | {:error, term()}
  def list_models(provider) do
    Arcanum.Gateway.list_models(Inference.enrich_provider(provider))
  end

  @spec embed(map(), String.t(), String.t()) :: {:ok, [float()]} | {:error, term()}
  def embed(provider, model, input) do
    Arcanum.Gateway.embed(Inference.enrich_provider(provider), model, input)
  end

  @spec generate_image(map(), Intent.t(), keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def generate_image(provider, %Intent{} = intent, opts \\ []) do
    Arcanum.Gateway.generate_image(Inference.enrich_provider(provider), intent, opts)
  end

  @spec generate_video(map(), Intent.t(), keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def generate_video(provider, %Intent{} = intent, opts \\ []) do
    Arcanum.Gateway.generate_video(Inference.enrich_provider(provider), intent, opts)
  end
end
