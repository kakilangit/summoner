defmodule Summoner.A2A.AgentBridge do
  @moduledoc """
  A2A Agent bridge — connects the A2A protocol to Summoner's ReAct loop.

  Each Herald (A2A server) gets one AgentBridge GenServer, started on demand.
  Implements `A2A.Agent` behaviour and the GenServer protocol expected by
  `A2A.Plug` (`:get_agent_card`, `{:message, ...}`, `{:get_task, ...}`,
  `{:cancel, ...}`, `{:list_tasks, ...}`).

  ## Process Registration

  Registered via `Summoner.A2ARegistry` with key `{:a2a_bridge, server_id}`.
  """

  use GenServer

  @behaviour A2A.Agent

  require Logger

  alias Summoner.A2A, as: SummonerA2A
  alias Summoner.A2A.ContentAdapter
  alias Summoner.A2A.TaskStore, as: SummonerTaskStore
  alias Summoner.Agents.Agent
  alias Summoner.Agents.Server, as: AgentServer
  alias Summoner.Conversations
  alias Summoner.Conversations.Content
  alias Summoner.MCP
  alias Summoner.Skills

  alias A2A.Agent.Runtime, as: AgentRuntime
  alias A2A.Agent.State, as: AgentState
  alias A2A.Artifact
  alias A2A.Message
  alias A2A.Part

  @registry Summoner.A2ARegistry

  # -------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------

  @doc """
  Starts a bridge process for the given A2A server.
  """
  def start_link(opts) do
    server_id = Keyword.fetch!(opts, :server_id)
    name = via(server_id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Ensures a bridge is running for the given A2A server, starting on demand.
  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  def ensure_started(server_id) do
    case Registry.lookup(@registry, {:a2a_bridge, server_id}) do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid), do: {:ok, pid}, else: do_start(server_id)

      [] ->
        do_start(server_id)
    end
  end

  defp do_start(server_id) do
    opts = [server_id: server_id]

    case DynamicSupervisor.start_child(Summoner.A2ASupervisor, {__MODULE__, opts}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the via tuple for registry lookup.
  """
  def via(server_id) do
    {:via, Registry, {@registry, {:a2a_bridge, server_id}}}
  end

  # -------------------------------------------------------------------
  # A2A.Agent behaviour callbacks
  # -------------------------------------------------------------------

  @impl A2A.Agent
  def agent_card do
    # Called from GenServer context via handle_call(:get_agent_card, ...)
    # Process dictionary is set in init
    build_agent_card(Process.get(:a2a_server), Process.get(:summoner_agent))
  end

  @impl A2A.Agent
  def handle_message(message, context) do
    a2a_server = Process.get(:a2a_server)
    agent = Process.get(:summoner_agent)

    if agent do
      do_handle_message(agent, a2a_server, message, context)
    else
      {:error, "Agent not configured for this bridge"}
    end
  end

  @impl A2A.Agent
  def handle_cancel(_context), do: :ok

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    server_id = Keyword.fetch!(opts, :server_id)
    a2a_server = SummonerA2A.get_server_with_agent!(server_id)
    agent = a2a_server.agent

    Process.put(:a2a_server, a2a_server)
    Process.put(:summoner_agent, agent)

    Logger.info("A2A bridge started for agent #{agent.name} (server: #{server_id})")

    {:ok,
     %AgentState{
       module: __MODULE__,
       task_store: {SummonerTaskStore, server_id}
     }}
  end

  @impl GenServer
  def handle_call(:get_agent_card, _from, state) do
    {:reply, agent_card(), state}
  end

  def handle_call({:message, message, opts}, from, state) do
    task_id = Keyword.get(opts, :task_id)
    context_id = Keyword.get(opts, :context_id)
    metadata = Keyword.get(opts, :metadata, %{})

    result =
      if task_id do
        case AgentState.get_task(state, task_id) do
          {:ok, task} ->
            AgentRuntime.continue_task(__MODULE__, message, task, state)

          {:error, :not_found} ->
            {:error, :not_found}
        end
      else
        {:ok,
         AgentRuntime.process_message(
           __MODULE__,
           message,
           context_id,
           state,
           metadata
         )}
      end

    case result do
      {:ok, {task, state}} ->
        task = maybe_wrap_stream(task, from)
        state = AgentState.put_task(state, task)
        {:reply, {:ok, task}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:cancel, task_id}, _from, state) do
    case AgentState.get_task(state, task_id) do
      {:ok, task} ->
        do_cancel_task(task, state)

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:get_task, task_id}, _from, state) do
    {:reply, AgentState.get_task(state, task_id), state}
  end

  def handle_call({:list_tasks, params}, _from, state) do
    {:reply, AgentState.list_tasks(state, params), state}
  end

  @impl GenServer
  def handle_cast({:stream_done, task_id, parts}, state) do
    case AgentState.get_task(state, task_id) do
      {:ok, task} ->
        artifact = Artifact.new(parts)
        agent_msg = Message.new_agent(parts)
        task = %{task | artifacts: task.artifacts ++ [artifact]}
        task = %{task | history: task.history ++ [agent_msg]}
        task = %{task | metadata: Map.delete(task.metadata, :stream)}
        task = AgentState.transition(task, :completed)
        state = AgentState.put_task(state, task)
        {:noreply, state}

      {:error, :not_found} ->
        {:noreply, state}
    end
  end

  # -------------------------------------------------------------------
  # Cancel handling
  # -------------------------------------------------------------------

  defp do_cancel_task(%{status: %{state: state}} = task, gen_state)
       when state in [:completed, :canceled, :failed] do
    _ = task
    {:reply, {:error, :not_cancelable}, gen_state}
  end

  defp do_cancel_task(task, gen_state) do
    context = %{
      task_id: task.id,
      context_id: task.context_id,
      history: task.history,
      metadata: task.metadata
    }

    case AgentRuntime.run_cancel(__MODULE__, context) do
      :ok ->
        task = AgentState.transition(task, :canceled)
        gen_state = AgentState.put_task(gen_state, task)
        {:reply, :ok, gen_state}

      {:error, reason} ->
        {:reply, {:error, reason}, gen_state}
    end
  end

  # -------------------------------------------------------------------
  # Message handling
  # -------------------------------------------------------------------

  defp do_handle_message(agent, a2a_server, message, context) do
    content_blocks = ContentAdapter.parts_to_content(message.parts)
    text = Content.text_only(content_blocks)

    conversation_id = resolve_conversation(agent, a2a_server, context)
    workspace_id = agent.workspace_id

    case AgentServer.ensure_started(workspace_id, agent.id) do
      :ok ->
        invoke_and_convert(workspace_id, agent.id, conversation_id, text)

      {:error, reason} ->
        Logger.error("Failed to start agent server for A2A bridge: #{inspect(reason)}")
        {:error, "Agent unavailable"}
    end
  end

  defp invoke_and_convert(workspace_id, agent_id, conversation_id, message) do
    params = %{
      conversation_id: conversation_id,
      message: message,
      scope: %{user: nil}
    }

    case AgentServer.invoke(workspace_id, agent_id, params) do
      {:ok, invocation} ->
        parts = extract_response_parts(invocation)
        {:reply, parts}

      {:error, reason} ->
        Logger.warning("A2A invocation failed: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end

  defp resolve_conversation(agent, a2a_server, context) do
    context_id = context.context_id

    if context_id do
      case SummonerA2A.get_task_conversation(a2a_server.id, context_id) do
        {:ok, conversation_id} -> conversation_id
        :not_found -> create_a2a_conversation(agent)
      end
    else
      create_a2a_conversation(agent)
    end
  end

  defp create_a2a_conversation(agent) do
    attrs = %{
      workspace_id: agent.workspace_id,
      primary_agent_id: agent.id,
      title: "A2A Session",
      kind: :a2a
    }

    case Conversations.create_system_conversation(attrs) do
      {:ok, conversation} -> conversation.id
      {:error, reason} -> raise "Failed to create A2A conversation: #{inspect(reason)}"
    end
  end

  defp extract_response_parts(invocation) do
    output = invocation.output || %{}
    content = output["content"] || output[:content]

    case content do
      nil ->
        response = output["response"] || output[:response] || ""
        [Part.Text.new(to_string(response))]

      blocks when is_list(blocks) ->
        ContentAdapter.content_to_parts(blocks)

      text when is_binary(text) ->
        [Part.Text.new(text)]
    end
  end

  defp build_agent_card(a2a_server, agent) do
    name = if agent, do: agent.callname, else: "unknown"

    description =
      if agent do
        Agent.description(agent) || truncate_description(system_prompt(agent)) || ""
      else
        ""
      end

    skills = build_skills(agent)

    capabilities = %{
      streaming: true,
      state_transition_history: true
    }

    security_schemes =
      if a2a_server && a2a_server.access_mode == :protected do
        %{"bearer" => %A2A.SecurityScheme.HTTPAuth{scheme: "bearer"}}
      else
        %{}
      end

    %{
      name: name,
      description: description || "",
      version: "0.1.0",
      skills: skills,
      opts: [
        capabilities: capabilities,
        security_schemes: security_schemes
      ]
    }
  end

  defp build_skills(nil), do: []

  defp build_skills(agent) do
    knowledge_skills = build_knowledge_skills(agent.id)
    tool_skills = build_tool_skills(agent.id)
    knowledge_skills ++ tool_skills
  end

  defp build_knowledge_skills(agent_id) do
    agent_id
    |> Skills.list_equipped_skills_internal()
    |> Enum.map(fn skill ->
      %{
        id: "knowledge:#{skill.id}",
        name: skill.name,
        description: truncate_description(skill.content),
        tags: ["knowledge"]
      }
    end)
  end

  defp build_tool_skills(agent_id) do
    agent_id
    |> MCP.list_equipped_servers()
    |> Enum.map(fn server ->
      %{
        id: "tool:#{server.id}",
        name: server.name,
        description: "MCP tool server: #{server.name}",
        tags: ["tool", to_string(server.transport)]
      }
    end)
  end

  defp truncate_description(nil), do: ""

  defp truncate_description(text) when is_binary(text) do
    text
    |> String.split("\n\n", parts: 2)
    |> List.first()
    |> String.slice(0, 500)
  end

  defp system_prompt(%{local_agent: %{system_prompt: prompt}}), do: prompt
  defp system_prompt(_), do: nil

  defp maybe_wrap_stream(%{metadata: %{stream: enum}} = task, {_pid, _ref}) do
    wrapped = AgentRuntime.wrap_stream(enum, self(), task.id)
    %{task | metadata: Map.put(task.metadata, :stream, wrapped)}
  end

  defp maybe_wrap_stream(task, _from), do: task
end
