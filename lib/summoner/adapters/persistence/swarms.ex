defmodule Summoner.Adapters.Persistence.Swarms do
  @moduledoc """
  The Swarms context.

  Manages swarm definitions — groups of agents that collaborate.
  UI name: Party.
  """

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Conversations
  alias Summoner.Adapters.Persistence.Pagination
  alias Summoner.Adapters.Persistence.Workspaces
  alias Summoner.Domain.Schemas.{Agent, Swarm, SwarmMember}
  alias Summoner.Repo

  @max_members 20

  # -------------------------------------------------------------------
  # Swarms
  # -------------------------------------------------------------------

  def create_swarm(%{user: _user}, attrs) do
    %Swarm{}
    |> Swarm.changeset(attrs)
    |> validate_coordinator_is_local()
    |> Repo.insert()
  end

  def update_swarm(%{user: _user}, %Swarm{} = swarm, attrs) do
    changeset = Swarm.changeset(swarm, attrs)

    changeset
    |> validate_coordinator_is_local()
    |> validate_max_turns_against_members(swarm)
    |> Repo.update()
  end

  def list_swarms(%{user: _user}, workspace_id) do
    Swarm
    |> Workspaces.where_workspace(workspace_id)
    |> order_by([c], asc: c.name)
    |> preload(members: [agent: [local_agent: :provider]])
    |> Repo.all()
  end

  @doc """
  Lists swarms for a workspace with pagination.
  """
  def list_swarms_paginated(%{user: _user}, workspace_id, opts \\ []) do
    page =
      Swarm
      |> Workspaces.where_workspace(workspace_id)
      |> Pagination.paginate(opts)

    %{page | entries: Repo.preload(page.entries, members: [agent: [local_agent: :provider]])}
  end

  def get_swarm!(%{user: _user}, workspace_id, swarm_id) do
    Swarm
    |> Workspaces.where_workspace(workspace_id)
    |> Repo.get!(swarm_id)
    |> Repo.preload([{:coordinator_agent, [local_agent: :provider]}, members: member_query()])
  end

  def delete_swarm(%{user: _user}, %Swarm{} = swarm) do
    Repo.delete(swarm)
  end

  # -------------------------------------------------------------------
  # Members
  # -------------------------------------------------------------------

  @doc """
  Adds an agent as a member at the end of the swarm's member list.
  """
  def add_member(%{user: _user}, attrs) do
    swarm_id = attrs[:swarm_id] || attrs["swarm_id"]
    agent_id = attrs[:agent_id] || attrs["agent_id"]
    current_count = member_count(swarm_id)
    max_turns = get_swarm_max_turns(swarm_id)

    cond do
      agent_deleted?(agent_id) ->
        {:error,
         %Ecto.Changeset{
           action: :insert,
           errors: [
             agent_id: {"cannot add a deleted summon to a party", []}
           ],
           valid?: false
         }}

      current_count >= max_turns ->
        {:error,
         %Ecto.Changeset{
           action: :insert,
           errors: [
             agent_id:
               {"cannot add more members than max turns (#{max_turns}). " <>
                  "Increase max turns first or remove existing members.", []}
           ],
           valid?: false
         }}

      reject_remote_in_relay?(swarm_id, agent_id) ->
        {:error,
         %Ecto.Changeset{
           action: :insert,
           errors: [
             agent_id:
               {"remote summons cannot participate in chain (relay) mode — " <>
                  "they cannot use the relay handoff tool", []}
           ],
           valid?: false
         }}

      true ->
        next_position = next_member_position(swarm_id)

        %SwarmMember{}
        |> SwarmMember.changeset(Map.put(attrs, :position, next_position))
        |> Repo.insert()
    end
  end

  def remove_member(%{user: _user}, %SwarmMember{} = member) do
    Repo.delete(member)
  end

  def list_members(swarm_id) do
    SwarmMember
    |> where([m], m.swarm_id == ^swarm_id)
    |> order_by([m], asc: m.position)
    |> preload(agent: [local_agent: :provider])
    |> Repo.all()
  end

  @doc """
  Reorders members by a list of member IDs in the desired order.
  Updates position for each member in a single transaction.
  """
  def reorder_members(%{user: _user}, swarm_id, member_ids) when is_list(member_ids) do
    Repo.transact(fn ->
      member_ids
      |> Enum.with_index()
      |> Enum.each(fn {member_id, position} ->
        SwarmMember
        |> where([m], m.id == ^member_id and m.swarm_id == ^swarm_id)
        |> Repo.update_all(set: [position: position])
      end)

      {:ok, list_members(swarm_id)}
    end)
  end

  defp next_member_position(swarm_id) do
    SwarmMember
    |> where([m], m.swarm_id == ^swarm_id)
    |> select([m], coalesce(max(m.position), -1) + 1)
    |> Repo.one()
    |> min(@max_members - 1)
  end

  defp member_count(swarm_id) do
    SwarmMember
    |> where([m], m.swarm_id == ^swarm_id)
    |> Repo.aggregate(:count)
  end

  defp get_swarm_max_turns(swarm_id) do
    Swarm
    |> where([s], s.id == ^swarm_id)
    |> select([s], s.max_turns)
    |> Repo.one() || 20
  end

  # -------------------------------------------------------------------
  # Agent type validation
  # -------------------------------------------------------------------

  defp validate_coordinator_is_local(changeset) do
    mode = Ecto.Changeset.get_field(changeset, :mode)
    coordinator_id = Ecto.Changeset.get_field(changeset, :coordinator_agent_id)

    if mode == :directed && is_binary(coordinator_id) do
      case Repo.get(Agent, coordinator_id) do
        %Agent{deleted_at: deleted_at} when not is_nil(deleted_at) ->
          Ecto.Changeset.add_error(
            changeset,
            :coordinator_agent_id,
            "references a deleted summon"
          )

        %Agent{type: :remote} ->
          Ecto.Changeset.add_error(
            changeset,
            :coordinator_agent_id,
            "must be a local summon — remote summons cannot coordinate parties"
          )

        _ ->
          changeset
      end
    else
      changeset
    end
  end

  defp reject_remote_in_relay?(swarm_id, agent_id) do
    swarm_mode =
      Swarm
      |> where([s], s.id == ^swarm_id)
      |> select([s], s.mode)
      |> Repo.one()

    if swarm_mode == :relay do
      case Repo.get(Agent, agent_id) do
        %Agent{type: :remote} -> true
        _ -> false
      end
    else
      false
    end
  end

  defp agent_deleted?(agent_id) do
    case Repo.get(Agent, agent_id) do
      %Agent{deleted_at: deleted_at} when not is_nil(deleted_at) -> true
      _ -> false
    end
  end

  defp validate_max_turns_against_members(changeset, swarm) do
    new_max = Ecto.Changeset.get_field(changeset, :max_turns)

    if new_max != swarm.max_turns do
      count = member_count(swarm.id)

      if count > new_max do
        Ecto.Changeset.add_error(
          changeset,
          :max_turns,
          "cannot be less than the number of members (%{count}). " <>
            "Remove members first or use a higher value.",
          count: count
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  @doc false
  def member_query do
    from(m in SwarmMember,
      order_by: [asc: m.position],
      preload: [agent: [local_agent: :provider, remote_agent: []]]
    )
  end

  # -------------------------------------------------------------------
  # Party Conversations
  # -------------------------------------------------------------------

  @doc """
  Lists conversations for a swarm with pagination.
  """
  def list_swarm_conversations_paginated(%{user: _user}, swarm_id, opts \\ []) do
    Conversations.Conversation
    |> where([c], c.kind == :swarm and c.swarm_id == ^swarm_id)
    |> Pagination.paginate(opts)
  end

  @doc """
  Creates a conversation linked to a swarm.

  Auto-adds all swarm members as conversation participants.
  The first member becomes the primary agent.
  """
  def create_conversation(%{user: _user} = scope, %Swarm{} = swarm) do
    members = list_members(swarm.id)

    if members == [] do
      {:error, :no_members}
    else
      do_create_conversation(scope, swarm, members)
    end
  end

  defp do_create_conversation(scope, swarm, members) do
    first_agent = hd(members).agent

    Repo.transact(fn ->
      with {:ok, conversation} <-
             Conversations.create_conversation(scope, %{
               workspace_id: swarm.workspace_id,
               primary_agent_id: first_agent.id,
               title: "#{swarm.name} Channel",
               kind: :swarm,
               swarm_id: swarm.id
             }),
           :ok <- add_remaining_participants(conversation, members) do
        {:ok, conversation}
      end
    end)
  end

  defp add_remaining_participants(conversation, members) do
    # First member is already added by create_conversation
    remaining = Enum.drop(members, 1)

    Enum.reduce_while(remaining, :ok, fn member, :ok ->
      case Conversations.add_participant(conversation.id, member.agent_id) do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end
end
