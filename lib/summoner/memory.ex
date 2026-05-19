defmodule Summoner.Memory do
  @moduledoc """
  Context assembly for invocations (The Memory).

  Assembles the full context window that gets sent to the inference
  provider. The assembly order follows RFC Section 2.4:

  1. System prompt (personality block + sacred instructions)
  2. Skill instructions (injected as system-level messages) — Phase 3
  3. MCP tool definitions — Phase 1.15
  4. Conversation history (last N messages, chronological)
  5. The user's new message
  """

  alias Arcanum.Intent
  alias Summoner.Conversations
  alias Summoner.Conversations.{Content, Message}
  alias Summoner.Media
  alias Summoner.Presets
  alias Summoner.Workspaces

  @doc """
  Assembles the context for an invocation.

  Returns a list of Intent-compatible message maps:
  `[%{role: :system | :user | :assistant | :tool, content: String.t()}]`

  ## Parameters

  - `conversation_id` — the conversation to load history from
  - `agent` — the Agent struct (needs `system_prompt`, `personality`)
  - `new_message` — the new user message content (string)
  - `opts`:
    - `:context_window` — number of history messages to load (default 20)
    - `:skills` — list of skill instruction strings to inject (default [])
    - `:tools` — list of MCP tool definition maps to inject (default [])
    - `:harness` — global harness guidelines prepended to system prompt (default from presets)
  """
  def assemble_context(conversation_id, agent, new_message, opts \\ []) do
    context_window = Keyword.get(opts, :context_window, 20)
    skills = Keyword.get(opts, :skills, [])
    tools = Keyword.get(opts, :tools, [])
    workspace_id = Keyword.get(opts, :workspace_id)
    harness = Keyword.get(opts, :harness)
    swarm_members = Keyword.get(opts, :swarm_members, [])

    system_prompt = build_system_prompt(agent, workspace_id, harness: harness)
    skill_messages = build_skill_messages(skills)
    tool_messages = build_tool_messages(tools)
    history = load_history(conversation_id, context_window, agent.id, swarm_members)

    tail =
      if new_message do
        content =
          cond do
            is_list(new_message) -> Content.to_intent_blocks(new_message)
            is_binary(new_message) -> Intent.text(new_message)
            true -> Intent.text("")
          end

        [%{role: :user, content: content}]
      else
        []
      end

    [system_prompt] ++ skill_messages ++ tool_messages ++ history ++ tail
  end

  @doc """
  Assembles context for a worker agent executing a delegated subtask.

  Workers receive only the system prompt + task description,
  not the full parent conversation history.
  """
  def assemble_worker_context(agent, task_description, opts \\ []) do
    harness = Keyword.get(opts, :harness)
    system_prompt = build_system_prompt(agent, agent.workspace_id, harness: harness)
    user_message = %{role: :user, content: Intent.text(task_description)}

    [system_prompt, user_message]
  end

  @doc """
  Builds the system prompt from an Agent's personality and instructions.

  Prepends the workspace harness (global operational guidelines) and
  appends workspace environment info (working directory) when workspace_id
  is provided.

  ## Options

  - `:harness` — custom harness text (falls back to preset default if nil)
  """
  def build_system_prompt(agent, workspace_id \\ nil, opts \\ []) do
    harness = Keyword.get(opts, :harness) || Presets.default_harness()

    parts =
      [harness, agent.local_agent.personality, agent.local_agent.system_prompt]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    env_block = workspace_env_block(workspace_id)
    parts = if env_block, do: parts ++ [env_block], else: parts

    git_block = git_context_block(workspace_id)
    parts = if git_block, do: parts ++ [git_block], else: parts

    %{role: :system, content: Intent.text(Enum.join(parts, "\n\n"))}
  end

  # -------------------------------------------------------------------
  # Internal
  # -------------------------------------------------------------------

  defp workspace_env_block(nil), do: nil

  defp workspace_env_block(workspace_id) do
    dir = Workspaces.workspace_dir(workspace_id)

    """
    ## Environment
    - Working directory: #{dir}
    - All file and shell tools are sandboxed to this directory.
    - IMPORTANT: Always use relative paths (e.g. "myfile.txt", "src/main.ex") for file operations.
    - Relative paths are automatically resolved against the working directory.
    - Do NOT try to construct or guess the absolute workspace path yourself.\
    """
  end

  defp git_context_block(nil), do: nil

  defp git_context_block(workspace_id) do
    dir = Workspaces.workspace_dir(workspace_id)
    Summoner.GitContext.build(dir)
  end

  defp build_skill_messages([]), do: []

  defp build_skill_messages(skills) do
    Enum.map(skills, fn instruction ->
      %{role: :system, content: Intent.text(instruction)}
    end)
  end

  defp build_tool_messages([]), do: []

  defp build_tool_messages(tools) do
    schema = Jason.encode!(tools)
    [%{role: :system, content: Intent.text("Available tools:\n#{schema}")}]
  end

  defp load_history(nil, _context_window, _agent_id, _members), do: []

  defp load_history(conversation_id, context_window, current_agent_id, swarm_members) do
    callname_map = build_callname_map(swarm_members)

    # Load the most recent summary (if any) to provide compacted context
    summary =
      case Conversations.latest_summary(conversation_id) do
        nil ->
          []

        msg ->
          [
            %{
              role: :system,
              content:
                Intent.text("## Previous Context Summary\n\n#{Content.text_only(msg.content)}")
            }
          ]
      end

    messages =
      Conversations.list_messages(conversation_id, limit: context_window, visibility: :public)

    # Preload attachments for vision support — collect all image attachment IDs
    attachments_map = preload_attachments(messages)

    recent =
      messages
      |> Enum.map(&message_to_map(&1, current_agent_id, callname_map, attachments_map))
      |> inject_missing_tool_results()

    summary ++ recent
  end

  defp preload_attachments(messages) do
    ids =
      messages
      |> Enum.flat_map(fn msg -> Content.image_attachment_ids(msg.content) end)
      |> Enum.uniq()

    case ids do
      [] -> %{}
      ids -> Media.get_attachments_map(ids)
    end
  end

  # Build a map of agent_id => callname from swarm members for attribution.
  defp build_callname_map([]), do: %{}

  defp build_callname_map(members) do
    Map.new(members, fn agent -> {agent.id, agent.callname} end)
  end

  # Detect assistant messages with tool_calls that lack corresponding :tool
  # result messages. This happens when an invocation is cancelled mid-execution.
  # Inject error results so the model doesn't get confused by orphaned calls.
  defp inject_missing_tool_results(messages) do
    {result, trailing} =
      Enum.reduce(messages, {[], MapSet.new()}, fn msg, {acc, pending_ids} ->
        case msg do
          %{role: :assistant, tool_calls: tool_calls} when is_list(tool_calls) ->
            new_ids =
              tool_calls |> Enum.map(&access_id/1) |> Enum.reject(&is_nil/1) |> MapSet.new()

            {acc ++ [msg], MapSet.union(pending_ids, new_ids)}

          %{role: :tool, tool_call_id: id} ->
            {acc ++ [msg], MapSet.delete(pending_ids, id)}

          _ ->
            # Non-tool message after pending tool calls means results are missing
            acc = acc ++ inject_errors_for(pending_ids)
            {acc ++ [msg], MapSet.new()}
        end
      end)

    # Handle trailing pending IDs at the end of history
    result ++ inject_errors_for(trailing)
  end

  defp access_id(%{id: id}), do: id
  defp access_id(%{"id" => id}), do: id
  defp access_id(_), do: nil

  defp inject_errors_for(ids) do
    if MapSet.size(ids) == 0 do
      []
    else
      Enum.map(ids, fn id ->
        %{role: :tool, content: Intent.text("[Tool execution was interrupted]"), tool_call_id: id}
      end)
    end
  end

  defp message_to_map(%Message{role: :tool} = msg, _agent_id, _callname_map, _att_map) do
    %{role: :tool, content: Content.to_intent_blocks(msg.content), tool_call_id: msg.tool_call_id}
  end

  defp message_to_map(%Message{tool_calls: tool_calls} = msg, _agent_id, _callname_map, att_map)
       when is_list(tool_calls) and tool_calls != [] do
    %{
      role: msg.role,
      content: msg.content |> Content.to_intent_blocks(att_map) |> text_only_blocks(),
      tool_calls: tool_calls
    }
    |> maybe_add_thinking(msg.thinking)
  end

  defp message_to_map(%Message{} = msg, current_agent_id, callname_map, att_map) do
    maybe_reattribute(msg, current_agent_id, callname_map, att_map)
    |> maybe_add_thinking(msg.thinking)
  end

  # In swarm mode, present assistant messages from OTHER agents as user-role
  # messages with attribution. This prevents the LLM from mimicking the format
  # in its own output (which happens with content prefixes on assistant messages).
  defp maybe_reattribute(
         %Message{role: :assistant, agent_id: agent_id} = msg,
         current_agent_id,
         callname_map,
         att_map
       )
       when agent_id != nil and agent_id != current_agent_id and callname_map != %{} do
    case Map.get(callname_map, agent_id) do
      nil ->
        %{
          role: :assistant,
          content: msg.content |> Content.to_intent_blocks(att_map) |> text_only_blocks()
        }

      callname ->
        %{
          role: :user,
          content: Intent.text("[#{callname} said]:\n#{Content.text_only(msg.content)}")
        }
    end
  end

  defp maybe_reattribute(%Message{role: :user} = msg, _current_agent_id, _callname_map, att_map) do
    %{role: :user, content: Content.to_intent_blocks(msg.content, att_map)}
  end

  defp maybe_reattribute(msg, _current_agent_id, _callname_map, att_map) do
    %{
      role: msg.role,
      content: msg.content |> Content.to_intent_blocks(att_map) |> text_only_blocks()
    }
  end

  # Providers reject image/video content blocks in non-user messages.
  # Strip them to text-only placeholders for assistant/system/tool roles.
  defp text_only_blocks(blocks) do
    Enum.map(blocks, fn
      %{type: type} when type in [:image_url, :image_base64, :image] ->
        %{type: :text, text: "[Image was here]"}

      %{type: :video} ->
        %{type: :text, text: "[Video was here]"}

      block ->
        block
    end)
  end

  defp maybe_add_thinking(map, nil), do: map
  defp maybe_add_thinking(map, ""), do: map
  defp maybe_add_thinking(map, thinking), do: Map.put(map, :thinking, thinking)
end
