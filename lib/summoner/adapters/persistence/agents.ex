defmodule Summoner.Adapters.Persistence.Agents do
  @moduledoc """
  The Agents context.

  Manages AI agent configurations within workspaces,
  including linking managers to workers. Agents come in two types:

  - `:local` — backed by a provider/model, runs the ReAct loop.
    Config stored in `local_agents` detail table.
  - `:remote` — backed by an external A2A agent.
    Config stored in `remote_agents` detail table.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Summoner.Adapters.Persistence.Conversations
  alias Summoner.Adapters.Persistence.Orchestration
  alias Summoner.Adapters.Persistence.Pagination
  alias Summoner.Adapters.Persistence.Workspaces
  alias Summoner.Domain.Events.InvocationStarted
  alias Summoner.Domain.Schemas.{Agent, AgentLink, LocalAgent, RemoteAgent}
  alias Summoner.Ports.Events
  alias Summoner.Repo
  alias Summoner.Services.A2A.ClientExecutor
  alias Summoner.Services.A2A.SkillResolver
  alias Summoner.Services.Agents.Server, as: AgentServer

  # -------------------------------------------------------------------
  # CRUD
  # -------------------------------------------------------------------

  @doc """
  Creates a local agent within a workspace.

  Atomically creates both the `agents` row and its `local_agents` detail row.
  """
  def create_agent(%{user: _user}, attrs) do
    attrs = maybe_generate_callname(attrs)
    {agent_attrs, local_attrs} = split_attrs(attrs)

    agent_attrs =
      if Map.has_key?(agent_attrs, "type") or Map.has_key?(agent_attrs, :type) do
        agent_attrs
      else
        type_key = if Enum.any?(Map.keys(agent_attrs), &is_binary/1), do: "type", else: :type
        Map.put(agent_attrs, type_key, :local)
      end

    Multi.new()
    |> Multi.insert(:agent, Agent.changeset(%Agent{}, agent_attrs))
    |> Multi.insert(:local_agent, fn %{agent: agent} ->
      %LocalAgent{agent_id: agent.id}
      |> LocalAgent.changeset(local_attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{agent: agent, local_agent: local_agent}} ->
        {:ok, %{agent | local_agent: local_agent}}

      {:error, :agent, changeset, _changes} ->
        {:error, changeset}

      {:error, :local_agent, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Creates a remote agent (Envoy) within a workspace.

  Atomically creates both the `agents` row (type: :remote) and its
  `remote_agents` detail row with A2A client configuration.
  """
  def create_remote_agent(%{user: _user}, attrs) do
    attrs = maybe_generate_callname(attrs)
    {agent_attrs, remote_attrs} = split_remote_attrs(attrs)

    agent_attrs =
      agent_attrs
      |> put_string_or_atom(:type, :remote)
      |> put_string_or_atom(:role, :worker)

    Multi.new()
    |> Multi.insert(:agent, Agent.changeset(%Agent{}, agent_attrs))
    |> Multi.insert(:remote_agent, fn %{agent: agent} ->
      %RemoteAgent{agent_id: agent.id}
      |> RemoteAgent.changeset(remote_attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{agent: agent, remote_agent: remote_agent}} ->
        {:ok, %{agent | remote_agent: remote_agent}}

      {:error, :agent, changeset, _changes} ->
        {:error, changeset}

      {:error, :remote_agent, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Updates a remote agent's configuration.
  """
  def update_remote_agent(%{user: _user}, %Agent{type: :remote} = agent, attrs) do
    {agent_attrs, remote_attrs} = split_remote_attrs(attrs)
    remote_agent = ensure_remote_agent_loaded(agent)

    Multi.new()
    |> Multi.update(:agent, Agent.changeset(agent, agent_attrs))
    |> Multi.update(:remote_agent, RemoteAgent.changeset(remote_agent, remote_attrs))
    |> Repo.transaction()
    |> case do
      {:ok, %{agent: agent, remote_agent: remote_agent}} ->
        {:ok, %{agent | remote_agent: remote_agent}}

      {:error, :agent, changeset, _changes} ->
        {:error, changeset}

      {:error, :remote_agent, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Gets a single agent scoped to a workspace.

  Raises `Ecto.NoResultsError` if not found.
  Preloads the type-specific detail (local_agent or remote_agent).
  """
  def get_agent!(%{user: _user}, workspace_id, agent_id) do
    Agent
    |> Workspaces.where_workspace(workspace_id)
    |> where([a], is_nil(a.deleted_at))
    |> Repo.get!(agent_id)
    |> preload_detail()
  end

  @doc """
  Lists all active agents for a workspace.
  """
  def list_agents(%{user: _user}, workspace_id) do
    Agent
    |> Workspaces.where_workspace(workspace_id)
    |> where([a], is_nil(a.deleted_at))
    |> order_by([f], asc: f.name)
    |> Repo.all()
    |> Enum.map(&preload_detail/1)
  end

  @doc """
  Lists all active remote agents for a workspace.
  """
  def list_remote_agents(%{user: _user}, workspace_id) do
    Agent
    |> Workspaces.where_workspace(workspace_id)
    |> where([a], a.type == :remote and is_nil(a.deleted_at))
    |> order_by([a], asc: a.name)
    |> preload(:remote_agent)
    |> Repo.all()
  end

  @doc """
  Lists agents for a workspace with pagination.
  """
  def list_agents_paginated(%{user: _user}, workspace_id, opts \\ []) do
    Agent
    |> Workspaces.where_workspace(workspace_id)
    |> where([a], is_nil(a.deleted_at))
    |> preload(local_agent: [:provider, :media_provider])
    |> Pagination.paginate(opts)
  end

  @doc """
  Updates an agent.

  For local agents, also updates the local_agent detail record.
  """
  def update_agent(%{user: _user}, %Agent{} = agent, attrs) do
    {agent_attrs, local_attrs} = split_attrs(attrs)

    case agent.type do
      :local ->
        local_agent = ensure_local_agent_loaded(agent)

        Multi.new()
        |> Multi.update(:agent, Agent.changeset(agent, agent_attrs))
        |> Multi.update(:local_agent, LocalAgent.changeset(local_agent, local_attrs))
        |> Repo.transaction()
        |> case do
          {:ok, %{agent: agent, local_agent: local_agent}} ->
            {:ok, %{agent | local_agent: local_agent}}

          {:error, :agent, changeset, _changes} ->
            {:error, changeset}

          {:error, :local_agent, changeset, _changes} ->
            {:error, changeset}
        end

      :remote ->
        {agent_attrs, remote_attrs} = split_remote_attrs(attrs)
        remote_agent = ensure_remote_agent_loaded(agent)

        Multi.new()
        |> Multi.update(:agent, Agent.changeset(agent, agent_attrs))
        |> Multi.update(:remote_agent, RemoteAgent.changeset(remote_agent, remote_attrs))
        |> Repo.transaction()
        |> case do
          {:ok, %{agent: agent, remote_agent: remote_agent}} ->
            {:ok, %{agent | remote_agent: remote_agent}}

          {:error, :agent, changeset, _changes} ->
            {:error, changeset}

          {:error, :remote_agent, changeset, _changes} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Soft-deletes an agent by setting `deleted_at`.

  Preserves conversation history and audit trail.
  """
  def delete_agent(%{user: _user}, %Agent{} = agent) do
    agent
    |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now()})
    |> Ecto.Changeset.foreign_key_constraint(:conversations,
      name: :conversations_primary_agent_id_fkey,
      message: "summon is still used by channels"
    )
    |> Ecto.Changeset.foreign_key_constraint(:conversation_participants,
      name: :conversation_participants_agent_id_fkey,
      message: "summon is still a participant in channels"
    )
    |> Ecto.Changeset.foreign_key_constraint(:pipeline_stages,
      name: :pipeline_stages_agent_id_fkey,
      message: "summon is still used by pipeline stages"
    )
    |> Ecto.Changeset.foreign_key_constraint(:swarm_members,
      name: :swarm_members_agent_id_fkey,
      message: "summon is still a member of a party"
    )
    |> Ecto.Changeset.foreign_key_constraint(:agent_skills,
      name: :agent_skills_agent_id_fkey,
      message: "summon still has skills equipped"
    )
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking agent changes.
  """
  def change_agent(%Agent{} = agent, attrs \\ %{}) do
    Agent.changeset(agent, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking local agent changes.
  """
  def change_local_agent(%LocalAgent{} = local_agent, attrs \\ %{}) do
    LocalAgent.changeset(local_agent, attrs)
  end

  # -------------------------------------------------------------------
  # Internal API (for infrastructure use)
  # -------------------------------------------------------------------

  @doc """
  Gets an agent with its local_agent and provider preloaded.

  Intended for infrastructure use (e.g. Agent GenServer startup).
  Raises `Ecto.NoResultsError` if not found.
  """
  def get_agent_with_provider!(agent_id) do
    Agent
    |> Repo.get!(agent_id)
    |> Repo.preload(local_agent: [provider: :api_key_secret])
  end

  # -------------------------------------------------------------------
  # Execution dispatch
  # -------------------------------------------------------------------

  @doc """
  Executes a message against an agent, dispatching by type.

  - `:local` — delegates to `Agents.Server.invoke/3` (ReAct loop)
  - `:remote` — delegates to `A2A.ClientExecutor.send_message/3`

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  def execute(%Agent{type: :local} = agent, message, opts) do
    workspace_id = agent.workspace_id
    conversation_id = Keyword.get(opts, :conversation_id)

    params = %{
      conversation_id: conversation_id,
      message: message,
      scope: Keyword.get(opts, :scope, %{user: nil})
    }

    AgentServer.invoke(workspace_id, agent.id, params)
  end

  def execute(%Agent{type: :remote} = agent, message, opts) do
    remote = ensure_remote_agent_loaded(agent)
    ClientExecutor.send_message(agent, remote, message, opts)
  end

  @task_supervisor Summoner.TaskSupervisor

  @doc """
  Synchronously executes a message against an agent, dispatching by type.
  Used by swarms which need the result before proceeding.

  For local agents, delegates to `AgentServer.invoke/3`.
  For remote agents, runs the A2A lifecycle synchronously.

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  def execute_sync(%Agent{type: :local} = agent, workspace_id, params) do
    AgentServer.invoke(workspace_id, agent.id, params)
  end

  def execute_sync(%Agent{type: :remote} = agent, workspace_id, params) do
    run_remote_invocation(agent, workspace_id, params)
  end

  @doc """
  Asynchronously executes a message against an agent, dispatching by type.

  For conversations: creates an invocation, sends the message, writes the
  response as an assistant message, and broadcasts status changes so LiveViews
  update automatically.

  - `:local` — delegates to `Agents.Server.invoke_async/3`
  - `:remote` — spawns a supervised task that runs the full A2A lifecycle

  Params must include `:conversation_id`, `:message`, and `:scope`.
  """
  def execute_async(%Agent{type: :local} = agent, workspace_id, params) do
    AgentServer.invoke_async(workspace_id, agent.id, params)
  end

  def execute_async(%Agent{type: :remote} = agent, workspace_id, params) do
    Task.Supervisor.start_child(@task_supervisor, fn ->
      run_remote_invocation(agent, workspace_id, params)
    end)
  end

  defp run_remote_invocation(agent, workspace_id, params) do
    conversation_id = Map.fetch!(params, :conversation_id)
    message = Map.fetch!(params, :message)
    scope = Map.fetch!(params, :scope)
    explicit_skill = Map.get(params, :skill)

    {:ok, invocation} =
      Orchestration.create_invocation(scope, %{
        workspace_id: workspace_id,
        agent_id: agent.id,
        conversation_id: conversation_id,
        status: :running,
        input: %{"message" => message}
      })

    Events.publish(%InvocationStarted{
      workspace_id: workspace_id,
      agent_id: agent.id,
      invocation_id: invocation.id
    })

    remote = ensure_remote_agent_loaded(agent)

    skill = explicit_skill || SkillResolver.resolve(remote.cached_agent_card, message)

    case ClientExecutor.send_message(agent, remote, message,
           conversation_id: conversation_id,
           skill: skill
         ) do
      {:ok, %{content: content}} ->
        Conversations.add_message(%{
          conversation_id: conversation_id,
          agent_id: agent.id,
          role: :assistant,
          visibility: :public,
          kind: :chat,
          content: content,
          invocation_id: invocation.id
        })

        Orchestration.update_invocation_status(invocation, :completed, %{
          end_reason: :completed,
          output: %{"response" => content_to_text(content)}
        })

      {:error, reason} ->
        error_text = if is_binary(reason), do: reason, else: inspect(reason)

        Conversations.add_message(%{
          conversation_id: conversation_id,
          agent_id: agent.id,
          role: :assistant,
          visibility: :public,
          kind: :chat,
          content: [%{"type" => "text", "text" => "**Error:** #{error_text}"}],
          invocation_id: invocation.id
        })

        Orchestration.update_invocation_status(invocation, :failed, %{
          end_reason: :failed,
          output: %{"error" => error_text}
        })
    end
  end

  defp content_to_text(content) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("\n", & &1["text"])
  end

  defp content_to_text(_), do: ""

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

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

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
    if Enum.any?(Map.keys(attrs), &is_binary/1) do
      Map.put(attrs, to_string(key), value)
    else
      Map.put(attrs, key, value)
    end
  end

  # Fields that belong to the agent base table
  @agent_fields ~w(name callname type role workspace_id)a
  @agent_string_fields ~w(name callname type role workspace_id)

  defp split_attrs(attrs) when is_map(attrs) do
    {agent, local} =
      Enum.reduce(attrs, {%{}, %{}}, fn {key, value}, {agent_acc, local_acc} ->
        atom_key = if is_binary(key), do: safe_to_atom(key), else: key

        if atom_key in @agent_fields do
          {Map.put(agent_acc, key, value), local_acc}
        else
          {agent_acc, Map.put(local_acc, key, value)}
        end
      end)

    {agent, local}
  end

  defp safe_to_atom(key) when is_binary(key) do
    if key in @agent_string_fields do
      String.to_existing_atom(key)
    else
      nil
    end
  rescue
    ArgumentError -> nil
  end

  defp preload_detail(%Agent{type: :local} = agent) do
    Repo.preload(agent, local_agent: [:provider, :media_provider])
  end

  defp preload_detail(%Agent{type: :remote} = agent) do
    Repo.preload(agent, :remote_agent)
  end

  defp preload_detail(%Agent{} = agent), do: agent

  defp ensure_local_agent_loaded(%Agent{local_agent: %LocalAgent{}} = agent) do
    agent.local_agent
  end

  defp ensure_local_agent_loaded(%Agent{} = agent) do
    Repo.preload(agent, :local_agent).local_agent
  end

  defp ensure_remote_agent_loaded(%Agent{remote_agent: %RemoteAgent{}} = agent) do
    agent.remote_agent
  end

  defp ensure_remote_agent_loaded(%Agent{} = agent) do
    Repo.preload(agent, :remote_agent).remote_agent
  end

  # Fields that belong to the remote_agents detail table
  @remote_agent_string_fields ~w(agent_card_url cached_agent_card auth_mode card_refreshed_at status timeout_s api_key_secret_id)

  defp split_remote_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, {%{}, %{}}, fn {key, value}, {agent_acc, remote_acc} ->
      atom_key = if is_binary(key), do: safe_to_atom_remote(key), else: key

      if atom_key in @agent_fields do
        {Map.put(agent_acc, key, value), remote_acc}
      else
        {agent_acc, Map.put(remote_acc, key, value)}
      end
    end)
  end

  defp safe_to_atom_remote(key) when is_binary(key) do
    combined = @agent_string_fields ++ @remote_agent_string_fields

    if key in combined do
      String.to_existing_atom(key)
    else
      nil
    end
  rescue
    ArgumentError -> nil
  end

  defp put_string_or_atom(attrs, key, value) do
    type_key = if Enum.any?(Map.keys(attrs), &is_binary/1), do: to_string(key), else: key
    Map.put_new(attrs, type_key, value)
  end
end
