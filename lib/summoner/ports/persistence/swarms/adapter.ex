defmodule Summoner.Ports.Persistence.Swarms.Adapter do
  @moduledoc "Behaviour for Swarms persistence operations."

  alias Summoner.Domain.Schemas.{Swarm, SwarmMember}

  # Swarms
  @callback create_swarm(map(), map()) :: {:ok, Swarm.t()} | {:error, Ecto.Changeset.t()}
  @callback update_swarm(map(), Swarm.t(), map()) ::
              {:ok, Swarm.t()} | {:error, Ecto.Changeset.t()}
  @callback list_swarms(map(), String.t()) :: [Swarm.t()]
  @callback list_swarms_paginated(map(), String.t()) :: struct()
  @callback list_swarms_paginated(map(), String.t(), keyword()) :: struct()
  @callback get_swarm!(map(), String.t(), String.t()) :: Swarm.t()
  @callback delete_swarm(map(), Swarm.t()) :: {:ok, Swarm.t()} | {:error, Ecto.Changeset.t()}

  # Members
  @callback add_member(map(), map()) :: {:ok, SwarmMember.t()} | {:error, Ecto.Changeset.t()}
  @callback remove_member(map(), SwarmMember.t()) ::
              {:ok, SwarmMember.t()} | {:error, Ecto.Changeset.t()}
  @callback list_members(String.t()) :: [SwarmMember.t()]
  @callback reorder_members(map(), String.t(), [String.t()]) ::
              {:ok, [SwarmMember.t()]} | {:error, term()}
  @callback member_query() :: Ecto.Query.t()
  @callback preload_members(Swarm.t()) :: Swarm.t()

  # Conversations
  @callback list_swarm_conversations_paginated(map(), String.t()) :: struct()
  @callback list_swarm_conversations_paginated(map(), String.t(), keyword()) :: struct()
  @callback create_conversation(map(), Swarm.t()) :: {:ok, struct()} | {:error, term()}
end
