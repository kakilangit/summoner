defmodule Summoner.Adapters.Persistence.A2A do
  @moduledoc """
  Context for A2A protocol integration.

  Manages Herald (A2A server), A2A tokens, and A2A task CRUD operations.
  """

  @behaviour Summoner.Ports.Persistence.A2A.Adapter

  import Ecto.Query, warn: false

  alias Summoner.Domain.Schemas.A2AServer
  alias Summoner.Domain.Schemas.A2ATask
  alias Summoner.Repo

  # -------------------------------------------------------------------
  # A2A Server (Herald) CRUD
  # -------------------------------------------------------------------

  @doc """
  Lists all A2A servers for a workspace.
  """
  def list_servers(%{user: _user}, workspace_id) do
    A2AServer
    |> where(workspace_id: ^workspace_id)
    |> order_by([s], desc: s.inserted_at)
    |> preload(:agent)
    |> Repo.all()
  end

  @doc """
  Gets a single A2A server by ID, scoped to workspace.
  """
  def get_server!(%{user: _user}, workspace_id, server_id) do
    A2AServer
    |> where(workspace_id: ^workspace_id, id: ^server_id)
    |> preload(:agent)
    |> Repo.one!()
  end

  @doc """
  Gets an A2A server by agent ID. Returns nil if not found.
  """
  def get_server_by_agent_id(agent_id) do
    A2AServer
    |> where(agent_id: ^agent_id)
    |> Repo.one()
  end

  @doc """
  Gets an A2A server by ID with agent and local_agent preloaded.
  Used by AgentBridge for initialization.
  """
  def get_server_with_agent!(server_id) do
    A2AServer
    |> where(id: ^server_id)
    |> preload(agent: :local_agent)
    |> Repo.one!()
  end

  @doc """
  Gets an enabled A2A server by agent ID.
  Used for routing inbound A2A requests.
  """
  def get_enabled_server_by_agent_id!(agent_id) do
    A2AServer
    |> where(agent_id: ^agent_id, enabled: true)
    |> preload(agent: :local_agent)
    |> Repo.one!()
  end

  @doc """
  Creates an A2A server (Herald) for a local agent.
  """
  def create_server(%{user: _user}, attrs) do
    %A2AServer{}
    |> A2AServer.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an A2A server without scope (for internal use, e.g. toggle from agent page).
  """
  def create_server(attrs) do
    %A2AServer{}
    |> A2AServer.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an A2A server (Herald).
  """
  def update_server(%{user: _user}, %A2AServer{} = server, attrs) do
    server
    |> A2AServer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates an A2A server without scope.
  """
  def update_server(%A2AServer{} = server, attrs) do
    server
    |> A2AServer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an A2A server (Herald).
  """
  def delete_server(%{user: _user}, %A2AServer{} = server) do
    Repo.delete(server)
  end

  @doc """
  Deletes an A2A server without scope.
  """
  def delete_server(%A2AServer{} = server) do
    Repo.delete(server)
  end

  @doc """
  Returns a changeset for tracking A2A server changes.
  """
  def change_server(%A2AServer{} = server, attrs \\ %{}) do
    A2AServer.changeset(server, attrs)
  end

  # -------------------------------------------------------------------
  # A2A Token CRUD — moved to Summoner.Adapters.Persistence.AccessTokens
  # -------------------------------------------------------------------

  # -------------------------------------------------------------------
  # A2A Task CRUD
  # -------------------------------------------------------------------

  @doc """
  Gets an A2A task by ID.
  """
  def get_task(task_id) do
    case Repo.get(A2ATask, task_id) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  @doc """
  Creates an A2A task record.
  """
  def create_task(attrs) do
    %A2ATask{}
    |> A2ATask.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an A2A task's state.
  """
  def update_task(%A2ATask{} = task, attrs) do
    task
    |> A2ATask.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists A2A tasks by context ID.
  """
  def list_tasks_by_context(context_id) do
    A2ATask
    |> where(context_id: ^context_id)
    |> order_by([t], asc: t.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists A2A tasks for an A2A server (inbound).
  """
  def list_tasks_by_server(server_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    A2ATask
    |> where(a2a_server_id: ^server_id)
    |> order_by([t], desc: t.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Finds a conversation ID for a given server and context_id.
  Returns `{:ok, conversation_id}` or `:not_found`.
  """
  def get_task_conversation(server_id, context_id) do
    task =
      A2ATask
      |> where(a2a_server_id: ^server_id, context_id: ^context_id)
      |> where([t], not is_nil(t.conversation_id))
      |> order_by([t], desc: t.inserted_at)
      |> limit(1)
      |> select([t], t.conversation_id)
      |> Repo.one()

    case task do
      nil -> :not_found
      id -> {:ok, id}
    end
  end

  # -------------------------------------------------------------------
  # Base URL
  # -------------------------------------------------------------------

  @doc """
  Constructs the public base URL for an A2A server endpoint.
  """
  def base_url(%A2AServer{} = server) do
    "#{SummonerWeb.Endpoint.url()}/agents/#{server.agent_id}"
  end
end
