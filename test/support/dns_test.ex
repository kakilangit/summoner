defmodule Summoner.Adapters.DNSTest do
  @moduledoc false

  @behaviour Summoner.Ports.DNS

  @impl true
  def lookup_mx(_domain), do: [{:mx, 10, ~c"mail.test"}]
end
