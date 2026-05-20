defmodule Summoner.Ports.Persistence.Pagination do
  @moduledoc "Port for pagination persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :pagination],
             Summoner.Adapters.Persistence.Pagination
           )

  defdelegate paginate(query), to: @adapter
  defdelegate paginate(query, opts), to: @adapter
end
