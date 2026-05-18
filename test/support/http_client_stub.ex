defmodule Summoner.HTTPClientStub do
  @moduledoc false
  @behaviour Summoner.HTTPClient

  @impl true
  def get(_url, _opts), do: {:error, :not_implemented}

  @impl true
  def post(_url, _opts), do: {:error, :not_implemented}
end
