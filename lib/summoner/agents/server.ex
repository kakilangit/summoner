defmodule Summoner.Agents.Server do
  @moduledoc """
  GenServer for a running Agent.

  Each Agent runs as a named process registered via `Registry`
  with key `{workspace_id, agent_id}`. The server manages
  concurrency limits, invocation lifecycle, and delegates to the
  ReAct loop for execution.

  ## State

  - `agent` — the Agent struct (with provider preloaded)
  - `active_tasks` — map of `{ref => {invocation_id, task_pid}}` for monitored Tasks
  - `pending_cancel` — set of invocation IDs pending cancellation
  """

  use GenServer

  require Logger

  alias Summoner.Agents
  alias Summoner.Agents.ProcessMonitor
  alias Summoner.Broadcasts
  alias Summoner.Ledger
  alias Summoner.MCP
  alias Summoner.Memory
  alias Summoner.Orchestration
  alias Summoner.Orchestration.{BuiltinTools, CompositeToolExecutor, McpToolExecutor, ReactLoop}
  alias Summoner.Skills

  @registry Summoner.AgentRegistry
  @supervisor Summoner.AgentSupervisor
  @task_supervisor Summoner.TaskSupervisor

  # -------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------

  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    workspace_id = Keyword.fetch!(opts, :workspace_id)
    name = via(workspace_id, agent_id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Ensures the Agent GenServer is running, starting it on demand if needed.
  """
  def ensure_started(workspace_id, agent_id) do
    case Registry.lookup(@registry, {workspace_id, agent_id}) do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid), do: :ok, else: do_start(workspace_id, agent_id)

      [] ->
        do_start(workspace_id, agent_id)
    end
  end

  defp do_start(workspace_id, agent_id) do
    opts = [workspace_id: workspace_id, agent_id: agent_id]

    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, opts}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # 5 minutes — matches the adapter receive_timeout
  @invoke_timeout :timer.minutes(5)

  @doc """
  Synchronously invokes the agent and waits for the result.

  Returns `{:ok, invocation}` if accepted, `{:error, reason}` if rejected.
  """
  def invoke(workspace_id, agent_id, params) do
    case ensure_started(workspace_id, agent_id) do
      :ok ->
        GenServer.call(via(workspace_id, agent_id), {:invoke, params}, @invoke_timeout)

      {:error, reason} ->
        Logger.error("Failed to start agent server: #{inspect(reason)}")
        {:error, :agent_unavailable}
    end
  end

  @doc """
  Invokes the Agent asynchronously (fire-and-forget).

  Results are broadcast via PubSub to the agent topic.
  Use this from LiveViews to avoid blocking the UI process.
  """
  def invoke_async(workspace_id, agent_id, params) do
    case ensure_started(workspace_id, agent_id) do
      :ok ->
        GenServer.cast(via(workspace_id, agent_id), {:invoke_async, params})

      {:error, reason} ->
        Logger.error("Failed to start agent server: #{inspect(reason)}")
        {:error, :agent_unavailable}
    end
  end

  @doc """
  Cancels a running invocation.
  """
  def cancel(workspace_id, agent_id, invocation_id) do
    GenServer.cast(via(workspace_id, agent_id), {:cancel, invocation_id})
  end

  @doc """
  Returns the via tuple for Registry lookup.
  """
  def via(workspace_id, agent_id) do
    {:via, Registry, {@registry, {workspace_id, agent_id}}}
  end

  @doc """
  Checks if an Agent server is running.
  """
  def alive?(workspace_id, agent_id) do
    case Registry.lookup(@registry, {workspace_id, agent_id}) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  # -------------------------------------------------------------------
  # Server callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    agent = Agents.get_agent_with_provider!(agent_id)

    {tool_executor, intent_tools} =
      load_tools(Keyword.get(opts, :tool_executor), agent.workspace_id, agent.id)

    state = %{
      agent: agent,
      active_tasks: %{},
      task_callers: %{},
      pending_cancel: MapSet.new(),
      pending_replies: %{},
      tool_executor: tool_executor,
      intent_tools: intent_tools,
      adapter_override: Keyword.get(opts, :adapter)
    }

    # Subscribe to agent config changes for tool refresh
    Broadcasts.subscribe("agent_config:#{agent.id}")
    ProcessMonitor.monitor(agent.workspace_id, agent.id, self())
    Logger.info("Agent server started: #{agent.name} (#{agent.id})")
    {:ok, state}
  end

  @impl true
  def handle_call({:invoke, params}, from, state) do
    conversation_id = Map.fetch!(params, :conversation_id)
    message = Map.fetch!(params, :message)
    scope = Map.fetch!(params, :scope)
    react_opts = Map.get(params, :react_opts, %{})

    if active_count(state) >= state.agent.max_concurrent_invocations do
      # Queue the invocation in DB, defer reply until it completes
      case create_queued_invocation(scope, state, conversation_id, message) do
        {:ok, invocation} ->
          state = put_pending_reply(state, invocation.id, from, react_opts)
          {:noreply, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      case start_invocation(scope, state, conversation_id, message, react_opts) do
        {:ok, invocation, state} ->
          # Defer reply until ReactLoop task completes so synchronous
          # callers (SwarmRunner) receive the finished invocation with output.
          state = put_pending_reply(state, invocation.id, from, react_opts)
          {:noreply, state}

        {:error, reason, state} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call(
        {:task_offer, subtask_id, description, parent_invocation_id},
        {caller_pid, _},
        state
      ) do
    if active_count(state) >= state.agent.max_concurrent_invocations do
      {:reply, {:error, :at_capacity}, state}
    else
      workspace_id = state.agent.workspace_id

      # Create a child invocation for this worker
      {:ok, invocation} =
        Orchestration.create_invocation(%{user: nil}, %{
          workspace_id: workspace_id,
          agent_id: state.agent.id,
          parent_invocation_id: parent_invocation_id,
          depth: 1,
          status: :queued,
          input: %{"subtask_id" => subtask_id, "description" => description},
          provider_name: state.agent.provider.name,
          model_name: state.agent.model
        })

      # Start the worker's ReAct loop
      settings = load_workspace_settings(workspace_id)

      context =
        Memory.assemble_worker_context(state.agent, description, harness: settings.harness)

      {tool_executor, intent_tools} = {state.tool_executor, state.intent_tools}

      task =
        Task.Supervisor.async_nolink(@task_supervisor, fn ->
          ReactLoop.run(
            state.agent,
            state.agent.provider,
            invocation,
            context,
            [
              tool_executor: tool_executor,
              tools: intent_tools,
              max_tool_output_chars: settings.max_tool_output_chars
            ] ++ maybe_adapter_opt(state)
          )
        end)

      state = put_task(state, task.ref, invocation.id, task.pid)
      state = put_task_caller(state, invocation.id, caller_pid, subtask_id)

      {:reply, {:ok, invocation.id}, state}
    end
  end

  @impl true
  def handle_cast({:invoke_async, params}, state) do
    conversation_id = Map.fetch!(params, :conversation_id)
    message = Map.fetch!(params, :message)
    scope = Map.fetch!(params, :scope)
    react_opts = Map.get(params, :react_opts, %{})

    if active_count(state) >= state.agent.max_concurrent_invocations do
      case create_queued_invocation(scope, state, conversation_id, message) do
        {:ok, _invocation} -> :ok
        {:error, reason} -> Logger.warning("Queued invocation failed: #{inspect(reason)}")
      end

      {:noreply, state}
    else
      case start_invocation(scope, state, conversation_id, message, react_opts) do
        {:ok, _invocation, state} -> {:noreply, state}
        {:error, _reason, state} -> {:noreply, state}
      end
    end
  end

  @impl true
  def handle_cast({:cancel, invocation_id}, state) do
    state = cancel_invocation_task(state, invocation_id)
    {:noreply, state}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completed — clean up
    Process.demonitor(ref, [:flush])
    {invocation_id, state} = pop_task(state, ref)

    case result do
      {:ok, invocation} ->
        Logger.info("Invocation #{invocation_id} completed")
        output = invocation.output || %{}
        notify_task_caller(state, invocation_id, :ok, output)
        maybe_reply_pending(state, invocation_id, {:ok, invocation})

      {:error, reason, _invocation} ->
        Logger.warning("Invocation #{invocation_id} failed: #{inspect(reason)}")
        notify_task_caller(state, invocation_id, :error, reason)
        maybe_reply_pending(state, invocation_id, {:error, reason})
    end

    state = pop_task_caller(state, invocation_id)
    state = pop_pending_reply(state, invocation_id)
    state = %{state | pending_cancel: MapSet.delete(state.pending_cancel, invocation_id)}
    state = maybe_dequeue(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    {invocation_id, state} = pop_task(state, ref)

    if invocation_id do
      Logger.error("Invocation #{invocation_id} task crashed: #{inspect(reason)}")

      # Best-effort: mark invocation as failed
      case Orchestration.get_invocation_by_id(invocation_id) do
        nil -> :ok
        inv -> Orchestration.update_invocation_status(inv, :failed, %{end_reason: :failed})
      end

      notify_task_caller(state, invocation_id, :error, {:task_crashed, reason})
      maybe_reply_pending(state, invocation_id, {:error, {:task_crashed, reason}})
    end

    state = pop_task_caller(state, invocation_id)
    state = pop_pending_reply(state, invocation_id)
    state = maybe_dequeue(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:refresh_tools, state) do
    {tool_executor, intent_tools} = load_tools(nil, state.agent.workspace_id, state.agent.id)
    Logger.info("Agent #{state.agent.name}: tools refreshed")
    {:noreply, %{state | tool_executor: tool_executor, intent_tools: intent_tools}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Agent server received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # -------------------------------------------------------------------
  # Internal
  # -------------------------------------------------------------------

  defp start_invocation(scope, state, conversation_id, message, react_opts) do
    # Reload agent from DB to pick up any changes (model, provider, etc.)
    agent = Agents.get_agent_with_provider!(state.agent.id)
    state = %{state | agent: agent}
    workspace_id = agent.workspace_id

    # Check workspace quota and budgets before creating invocation
    with :ok <- Ledger.check_workspace_quota(workspace_id),
         :ok <- Ledger.check_workspace_budget(workspace_id),
         :ok <- Ledger.check_agent_budget(agent.id, agent.budget_usd) do
      input =
        if message, do: %{"message" => message}, else: %{"continuation" => true}

      {:ok, invocation} =
        Orchestration.create_invocation(scope, %{
          workspace_id: workspace_id,
          agent_id: state.agent.id,
          conversation_id: conversation_id,
          status: :queued,
          input: input,
          provider_name: state.agent.provider.name,
          model_name: state.agent.model
        })

      # Assemble context first (before writing user message, so history
      # doesn't include it — assemble_context appends it as the final message)
      settings = load_workspace_settings(workspace_id)
      context_window = settings.context_window_messages

      context =
        Memory.assemble_context(conversation_id, state.agent, message,
          context_window: context_window,
          skills: load_skill_contents(state.agent.id),
          workspace_id: workspace_id,
          harness: settings.harness,
          swarm_members: Map.get(react_opts, :swarm_members, [])
        )

      # Use cached tools from state
      {tool_executor, intent_tools} = {state.tool_executor, state.intent_tools}

      # Start the ReAct loop in a monitored Task
      task =
        Task.Supervisor.async_nolink(@task_supervisor, fn ->
          ReactLoop.run(
            state.agent,
            state.agent.provider,
            invocation,
            context,
            [
              tool_executor: tool_executor,
              tools: intent_tools,
              pipeline_stage: Map.get(react_opts, :pipeline_stage, false),
              swarm: Map.get(react_opts, :swarm, false),
              swarm_members: Map.get(react_opts, :swarm_members, []),
              swarm_mode: Map.get(react_opts, :swarm_mode),
              max_tool_output_chars: settings.max_tool_output_chars
            ] ++ maybe_adapter_opt(state)
          )
        end)

      state = put_task(state, task.ref, invocation.id, task.pid)
      {:ok, invocation, state}
    else
      {:error, :quota_exceeded, details} ->
        log_and_reject(workspace_id, scope, state, "quota_exceeded", details)

      {:error, :budget_exceeded, details} ->
        log_and_reject(workspace_id, scope, state, "budget_exceeded", details)
    end
  end

  defp log_and_reject(workspace_id, scope, state, action, details) do
    Summoner.Audit.log(%{
      workspace_id: workspace_id,
      user_id: scope.user.id,
      agent_id: state.agent.id,
      action: action,
      detail: details
    })

    {:error, String.to_existing_atom(action), state}
  end

  defp create_queued_invocation(scope, state, conversation_id, message) do
    Orchestration.create_invocation(scope, %{
      workspace_id: state.agent.workspace_id,
      agent_id: state.agent.id,
      conversation_id: conversation_id,
      status: :queued,
      input: %{"message" => message},
      provider_name: state.agent.provider.name,
      model_name: state.agent.model
    })
  end

  defp maybe_dequeue(state) do
    if active_count(state) >= state.agent.max_concurrent_invocations do
      state
    else
      do_dequeue(state)
    end
  end

  defp do_dequeue(state) do
    case dequeue_next_invocation(state) do
      nil ->
        state

      invocation ->
        if Map.has_key?(state.pending_replies, invocation.id) do
          run_queued_invocation(state, invocation)
        else
          cancel_stale_and_continue(state, invocation)
        end
    end
  end

  defp run_queued_invocation(state, invocation) do
    message = get_in(invocation.input, ["message"])
    react_opts = get_pending_react_opts(state, invocation.id)
    {:ok, state} = start_invocation_from_queued(state, invocation, message, react_opts)
    state
  end

  defp cancel_stale_and_continue(state, invocation) do
    Logger.info("Skipping stale queued invocation #{invocation.id} (no pending reply)")

    case Orchestration.update_invocation_status(invocation, :cancelled, %{end_reason: :stale}) do
      {:ok, _} ->
        do_dequeue(state)

      {:error, reason} ->
        Logger.warning("Failed to cancel stale invocation #{invocation.id}: #{inspect(reason)}")

        state
    end
  end

  defp start_invocation_from_queued(state, invocation, message, react_opts) do
    # Reload agent from DB to pick up any changes (model, provider, etc.)
    agent = Agents.get_agent_with_provider!(state.agent.id)
    state = %{state | agent: agent}
    conversation_id = invocation.conversation_id

    settings = load_workspace_settings(state.agent.workspace_id)
    context_window = settings.context_window_messages

    context =
      Memory.assemble_context(conversation_id, state.agent, message,
        context_window: context_window,
        skills: load_skill_contents(state.agent.id),
        workspace_id: state.agent.workspace_id,
        harness: settings.harness,
        swarm_members: Map.get(react_opts, :swarm_members, [])
      )

    {tool_executor, intent_tools} = {state.tool_executor, state.intent_tools}

    task =
      Task.Supervisor.async_nolink(@task_supervisor, fn ->
        ReactLoop.run(
          state.agent,
          state.agent.provider,
          invocation,
          context,
          [
            tool_executor: tool_executor,
            tools: intent_tools,
            pipeline_stage: Map.get(react_opts, :pipeline_stage, false),
            swarm: Map.get(react_opts, :swarm, false),
            swarm_members: Map.get(react_opts, :swarm_members, []),
            swarm_mode: Map.get(react_opts, :swarm_mode),
            max_tool_output_chars: settings.max_tool_output_chars
          ] ++ maybe_adapter_opt(state)
        )
      end)

    state = put_task(state, task.ref, invocation.id, task.pid)
    {:ok, state}
  end

  defp dequeue_next_invocation(state) do
    Orchestration.dequeue_invocation(state.agent.id)
  end

  defp active_count(state), do: map_size(state.active_tasks)

  defp put_task(state, ref, invocation_id, task_pid) do
    %{state | active_tasks: Map.put(state.active_tasks, ref, {invocation_id, task_pid})}
  end

  defp pop_task(state, ref) do
    {{invocation_id, _pid}, active_tasks} = Map.pop(state.active_tasks, ref)
    {invocation_id, %{state | active_tasks: active_tasks}}
  end

  defp cancel_invocation_task(state, invocation_id) do
    # Find the task ref for this invocation and kill it
    case Enum.find(state.active_tasks, fn {_ref, {id, _pid}} -> id == invocation_id end) do
      {ref, {_id, task_pid}} ->
        # Safe to kill — tasks are not linked (async_nolink), so killing
        # the task won't crash this GenServer.
        Process.demonitor(ref, [:flush])
        Process.exit(task_pid, :kill)

        # Mark as cancelled in DB
        Orchestration.update_invocation_status_by_id(invocation_id, :cancelled, %{
          end_reason: :cancelled,
          completed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

        state = %{state | active_tasks: Map.delete(state.active_tasks, ref)}
        state = pop_pending_reply(state, invocation_id)
        state = pop_task_caller(state, invocation_id)
        maybe_dequeue(state)

      nil ->
        # Not actively running — just mark for cleanup
        %{state | pending_cancel: MapSet.put(state.pending_cancel, invocation_id)}
    end
  end

  defp put_task_caller(state, invocation_id, caller_pid, subtask_id) do
    %{state | task_callers: Map.put(state.task_callers, invocation_id, {caller_pid, subtask_id})}
  end

  defp pop_task_caller(state, invocation_id) do
    %{state | task_callers: Map.delete(state.task_callers, invocation_id)}
  end

  defp notify_task_caller(state, invocation_id, status, result) do
    case Map.get(state.task_callers, invocation_id) do
      {caller_pid, subtask_id} ->
        send(caller_pid, {:task_result, subtask_id, status, result})

      nil ->
        :ok
    end
  end

  defp load_workspace_settings(workspace_id) do
    Summoner.Workspaces.get_settings!(workspace_id)
  end

  defp load_tools(test_executor, _workspace_id, _agent_id) when not is_nil(test_executor) do
    {test_executor, nil}
  end

  defp load_tools(_test_executor, workspace_id, agent_id) do
    mcp_tools = MCP.list_tools_for_agent(workspace_id, agent_id)
    mcp_intent_tools = McpToolExecutor.to_intent_tools(mcp_tools)
    builtin_defs = BuiltinTools.tool_definitions()
    media_tool_defs = load_media_tools(agent_id)
    {CompositeToolExecutor, builtin_defs ++ media_tool_defs ++ mcp_intent_tools}
  end

  defp load_media_tools(agent_id) do
    agent = Agents.get_agent_with_provider!(agent_id)
    image_defs = load_media_tool(agent, :image, &BuiltinTools.generate_image_tool_definition/0)
    video_defs = load_media_tool(agent, :video, &BuiltinTools.generate_video_tool_definition/0)
    image_defs ++ video_defs
  end

  defp load_media_tool(agent, type, definition_fn) do
    case Summoner.MediaProviders.resolve_media_provider(agent, type) do
      nil -> []
      _media_provider -> definition_fn.()
    end
  end

  defp load_skill_contents(agent_id) do
    agent_id
    |> Skills.list_equipped_skills_internal()
    |> Enum.map(& &1.content)
  end

  # -------------------------------------------------------------------
  # Pending replies — deferred GenServer.reply for queued invocations
  # -------------------------------------------------------------------

  defp put_pending_reply(state, invocation_id, from, react_opts) do
    %{state | pending_replies: Map.put(state.pending_replies, invocation_id, {from, react_opts})}
  end

  defp pop_pending_reply(state, invocation_id) do
    %{state | pending_replies: Map.delete(state.pending_replies, invocation_id)}
  end

  defp get_pending_react_opts(state, invocation_id) do
    case Map.get(state.pending_replies, invocation_id) do
      {_from, react_opts} -> react_opts
      nil -> %{}
    end
  end

  defp maybe_reply_pending(state, invocation_id, reply) do
    case Map.get(state.pending_replies, invocation_id) do
      {from, _react_opts} -> GenServer.reply(from, reply)
      nil -> :ok
    end
  end

  defp maybe_adapter_opt(%{adapter_override: nil}), do: []
  defp maybe_adapter_opt(%{adapter_override: adapter}), do: [adapter: adapter]
end
