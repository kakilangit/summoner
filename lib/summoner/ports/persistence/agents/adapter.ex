defmodule Summoner.Ports.Persistence.Agents.Adapter do
  @moduledoc "Behaviour for agent persistence operations."

  # CRUD
  @callback create_agent(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback create_remote_agent(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_remote_agent(map(), struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback get_agent!(map(), String.t(), String.t()) :: struct()
  @callback list_agents(map(), String.t()) :: [struct()]
  @callback list_remote_agents(map(), String.t()) :: [struct()]
  @callback list_agents_paginated(map(), String.t()) :: struct()
  @callback list_agents_paginated(map(), String.t(), keyword()) :: struct()
  @callback update_agent(map(), struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_agent(map(), struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback change_agent(struct()) :: Ecto.Changeset.t()
  @callback change_agent(struct(), map()) :: Ecto.Changeset.t()
  @callback change_local_agent(struct()) :: Ecto.Changeset.t()
  @callback change_local_agent(struct(), map()) :: Ecto.Changeset.t()

  # Preloading
  @callback preload_agent(struct()) :: struct()

  # Internal API
  @callback get_agent_with_provider!(String.t()) :: struct()

  # Internal API (unscoped)
  @callback update_remote_agent_card(struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}

  # Execution
  @callback execute(struct(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback execute_sync(struct(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  @callback execute_async(struct(), String.t(), map()) :: {:ok, pid()} | {:error, term()}

  # Linking
  @callback link_agents(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback unlink_agents(map(), String.t(), String.t()) ::
              {:ok, struct()} | {:error, :not_found}
  @callback list_linked_workers(map(), String.t()) :: [struct()]
end
