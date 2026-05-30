defmodule Summoner.Adapters.DNS do
  @moduledoc """
  DNS adapter backed by the Erlang resolver.
  """

  @behaviour Summoner.Ports.DNS

  @impl true
  def lookup_mx(domain) when is_binary(domain) do
    :inet_res.lookup(to_charlist(domain), :in, :mx)
  end
end
