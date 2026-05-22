defmodule Summoner.Ports.Persistence.AgentMemories.Adapter do
  @moduledoc "Behaviour for agent memory persistence operations."

  @callback create_memory(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback get_memory!(String.t()) :: struct()
  @callback list_by_agent(String.t(), keyword()) :: [struct()]
  @callback update_memory(struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_memory(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback cosine_search(String.t(), list(), keyword()) :: [struct()]
  @callback update_access(struct()) :: {:ok, struct()}
  @callback decay_batch(DateTime.t(), float()) :: {integer(), nil}
  @callback prune_below(String.t(), float()) :: {integer(), nil}
  @callback count_by_agent(String.t()) :: integer()
end
