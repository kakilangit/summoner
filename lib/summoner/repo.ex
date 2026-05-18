defmodule Summoner.Repo do
  use Ecto.Repo,
    otp_app: :summoner,
    adapter: Ecto.Adapters.Postgres
end
