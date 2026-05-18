Postgrex.Types.define(
  Summoner.PostgrexTypes,
  [Pgvector.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions()
)
