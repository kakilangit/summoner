defmodule Summoner.HTTPClient do
  @moduledoc """
  Behaviour for HTTP clients used by inference adapters.

  Allows mocking HTTP calls in tests via Mox.
  """

  @callback get(url :: String.t(), opts :: keyword()) :: {:ok, map()} | {:error, term()}
  @callback post(url :: String.t(), opts :: keyword()) :: {:ok, map()} | {:error, term()}
end
