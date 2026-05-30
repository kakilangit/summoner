defmodule Summoner.Ports.DNS do
  @moduledoc """
  Behaviour for DNS lookups used by validation logic.
  """

  @callback lookup_mx(String.t()) :: list()
end
