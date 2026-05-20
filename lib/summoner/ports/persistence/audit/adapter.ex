defmodule Summoner.Ports.Persistence.Audit.Adapter do
  @moduledoc "Behaviour for audit persistence operations."

  @callback log(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_logs(String.t()) :: [struct()]
  @callback list_logs(String.t(), keyword()) :: [struct()]
end
