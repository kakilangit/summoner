defmodule Summoner.Ports.Persistence.Pagination.Adapter do
  @moduledoc "Behaviour for pagination persistence operations."

  @callback paginate(Ecto.Queryable.t()) :: Summoner.Adapters.Persistence.Pagination.t()
  @callback paginate(Ecto.Queryable.t(), keyword()) ::
              Summoner.Adapters.Persistence.Pagination.t()
end
