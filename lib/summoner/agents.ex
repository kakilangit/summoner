defmodule Summoner.Agents do
  @moduledoc """
  The Agents context.

  Manages AI agent configurations within workspaces,
  including linking managers to workers.
  """

  import Ecto.Query, warn: false

  alias Summoner.Agents.{Agent, AgentLink}
  alias Summoner.Pagination
  alias Summoner.Repo
  alias Summoner.Workspaces

  # -------------------------------------------------------------------
  # CRUD
  # -------------------------------------------------------------------

  @doc """
  Creates an agent within a workspace.
  """
  def create_agent(%{user: _user}, attrs) do
    attrs = maybe_generate_callname(attrs)

    %Agent{}
    |> Agent.changeset(attrs)
    |> Repo.insert()
  end

  defp maybe_generate_callname(attrs) do
    callname = attrs[:callname] || attrs["callname"]
    name = attrs[:name] || attrs["name"]

    if callname_blank?(callname) && is_binary(name) do
      generated = Agent.to_callname(name)
      put_attr(attrs, :callname, generated)
    else
      attrs
    end
  end

  defp callname_blank?(nil), do: true
  defp callname_blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp callname_blank?(_), do: false

  defp put_attr(attrs, key, value) when is_map(attrs) do
    if Map.has_key?(attrs, "callname") do
      Map.put(attrs, "callname", value)
    else
      Map.put(attrs, key, value)
    end
  end

  @doc """
  Gets a single agent scoped to a workspace.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_agent!(%{user: _user}, workspace_id, agent_id) do
    Agent
    |> Workspaces.where_workspace(workspace_id)
    |> Repo.get!(agent_id)
  end

  @doc """
  Lists all agents for a workspace.
  """
  def list_agents(%{user: _user}, workspace_id) do
    Agent
    |> Workspaces.where_workspace(workspace_id)
    |> order_by([f], asc: f.name)
    |> Repo.all()
  end

  @doc """
  Lists agents for a workspace with pagination.
  """
  def list_agents_paginated(%{user: _user}, workspace_id, opts \\ []) do
    Agent
    |> Workspaces.where_workspace(workspace_id)
    |> Pagination.paginate(opts)
  end

  @doc """
  Updates an agent.
  """
  def update_agent(%{user: _user}, %Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an agent.
  """
  def delete_agent(%{user: _user}, %Agent{} = agent) do
    agent
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.foreign_key_constraint(:conversations,
      name: :conversations_primary_agent_id_fkey,
      message: "familiar is still used by séances"
    )
    |> Ecto.Changeset.foreign_key_constraint(:conversation_participants,
      name: :conversation_participants_agent_id_fkey,
      message: "familiar is still a participant in séances"
    )
    |> Ecto.Changeset.foreign_key_constraint(:pipeline_stages,
      name: :pipeline_stages_agent_id_fkey,
      message: "familiar is still used by pipeline stages"
    )
    |> Ecto.Changeset.foreign_key_constraint(:swarm_members,
      name: :swarm_members_agent_id_fkey,
      message: "familiar is still a member of a coven"
    )
    |> Ecto.Changeset.foreign_key_constraint(:agent_skills,
      name: :agent_skills_agent_id_fkey,
      message: "familiar still has skills equipped"
    )
    |> Repo.delete()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking agent changes.
  """
  def change_agent(%Agent{} = agent, attrs \\ %{}) do
    Agent.changeset(agent, attrs)
  end

  # -------------------------------------------------------------------
  # Internal API (for infrastructure use)
  # -------------------------------------------------------------------

  @doc """
  Gets an agent with its provider preloaded.

  Intended for infrastructure use (e.g. Agent GenServer startup).
  """
  def get_agent_with_provider!(agent_id) do
    Agent
    |> Repo.get!(agent_id)
    |> Repo.preload(provider: :api_key_secret)
  end

  # -------------------------------------------------------------------
  # Linking
  # -------------------------------------------------------------------

  @doc """
  Links an agent to a worker with a collaboration pattern.
  """
  def link_agents(%{user: _user}, attrs) do
    %AgentLink{}
    |> AgentLink.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Removes a link between an agent and a worker.

  Returns `{:ok, link}` or `{:error, :not_found}`.
  """
  def unlink_agents(%{user: _user}, manager_id, worker_id) do
    case Repo.get_by(AgentLink, manager_id: manager_id, worker_id: worker_id) do
      nil -> {:error, :not_found}
      link -> Repo.delete(link)
    end
  end

  @doc """
  Lists all workers linked to an agent.
  """
  def list_linked_workers(%{user: _user}, manager_id) do
    AgentLink
    |> where([l], l.manager_id == ^manager_id)
    |> preload(:worker)
    |> Repo.all()
    |> Enum.map(& &1.worker)
  end
end
