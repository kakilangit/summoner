defmodule Summoner.Services.Swarms.SwarmCoordinator do
  @moduledoc """
  Handles directed-mode routing for swarms.

  The coordinator agent receives a meta-prompt asking who should respond
  next. It outputs a JSON routing decision using agent callnames.
  After each agent finishes its turn, the coordinator is consulted again
  to decide whether to route to another agent or end the conversation.
  """

  require Logger

  alias Arcanum.{Intent, Response}
  alias Summoner.Domain.Schemas.Swarm
  alias Summoner.Domain.Types.Content
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Conversations
  alias Summoner.Services.Inference

  @doc """
  Calls the coordinator agent's LLM to determine the next agent.

  Returns `{:ok, agent, directive}` or `{:done, reason}`.

  The `opts` keyword list supports:
  - `:min_agents` — minimum distinct agents that must respond before
    `__done__` is accepted (default: `min(2, length(members))`)
  """
  def route(%Swarm{mode: :directed} = swarm, conversation, members, opts \\ []) do
    coordinator = Agents.get_agent_with_provider!(swarm.coordinator_agent_id)
    responded = agents_responded(conversation, members)
    min_agents = Keyword.get(opts, :min_agents, min(2, length(members)))

    system_prompt = build_meta_prompt(members, responded, min_agents)
    messages = build_context_messages(conversation, members)
    context = [%{role: :system, content: Intent.text(system_prompt)}] ++ messages

    intent = %Intent{
      messages: context,
      model: coordinator.local_agent.model,
      tools: nil,
      max_tokens: 1024
    }

    routing_ctx = %{
      responded: responded,
      min_agents: min_agents,
      members: members
    }

    call_coordinator(coordinator.local_agent.provider, intent, routing_ctx)
  end

  defp call_coordinator(provider, intent, routing_ctx) do
    case Inference.Gateway.chat(provider, intent) do
      {:ok, %Response{content: content}} ->
        parse_routing_decision(content, routing_ctx)

      {:error, reason} ->
        Logger.error("Coordinator routing failed: #{inspect(reason)}")
        fallback_to_first(routing_ctx.members, nil)
    end
  end

  # Returns the set of member callnames that have posted assistant messages.
  defp agents_responded(conversation, members) do
    member_map = Map.new(members, fn a -> {a.id, a.callname} end)

    conversation.id
    |> Conversations.list_messages(visibility: :public, limit: 50)
    |> Enum.reduce(MapSet.new(), fn msg, acc ->
      if msg.role == :assistant and Map.has_key?(member_map, msg.agent_id) do
        MapSet.put(acc, Map.fetch!(member_map, msg.agent_id))
      else
        acc
      end
    end)
  end

  defp build_context_messages(conversation, members) do
    conversation.id
    |> Conversations.list_messages(visibility: :public, limit: 20)
    |> Enum.map(&format_context_message(&1, members))
  end

  defp format_context_message(msg, members) do
    label = role_label(msg.role, msg.agent_id, members)
    # Present all history as user-role messages to the coordinator LLM
    # to avoid consecutive assistant messages (which some providers reject)
    %{role: :user, content: Intent.text("[#{label}]: #{Content.text_only(msg.content)}")}
  end

  defp role_label(:user, _agent_id, _members), do: "User"
  defp role_label(:system, _agent_id, _members), do: "System"

  defp role_label(:assistant, agent_id, members) do
    agent_callname(agent_id, members) || "assistant"
  end

  defp role_label(_role, _agent_id, _members), do: "other"

  defp agent_callname(nil, _members), do: nil

  defp agent_callname(id, members) do
    Enum.find_value(members, fn a -> if a.id == id, do: a.callname end)
  end

  # -------------------------------------------------------------------
  # Meta-prompt
  # -------------------------------------------------------------------

  defp build_meta_prompt(members, responded, min_agents) do
    member_list =
      Enum.map_join(members, "\n", fn agent ->
        la = agent.local_agent
        description = (la && la.system_prompt) || (la && la.personality) || "No description"
        truncated = String.slice(description, 0, 200)
        status = if MapSet.member?(responded, agent.callname), do: " [HAS RESPONDED]", else: ""
        "- @#{agent.callname} (#{agent.name})#{status}: #{truncated}"
      end)

    responded_count = MapSet.size(responded)
    not_yet = Enum.reject(members, fn a -> MapSet.member?(responded, a.callname) end)

    not_yet_list =
      case not_yet do
        [] -> "All agents have responded."
        agents -> "Not yet heard from: " <> Enum.map_join(agents, ", ", &"@#{&1.callname}")
      end

    threshold_note =
      if responded_count < min_agents do
        """
        IMPORTANT: Only #{responded_count}/#{min_agents} agents have responded so far.
        You MUST route to another agent. Do NOT respond "__done__" yet.
        """
      else
        ""
      end

    """
    You are a routing coordinator for a multi-agent collaboration.
    Output ONLY a JSON object, nothing else.

    Format:
    {"next": "@callname", "reason": "what this agent should contribute"}
    {"next": "__done__", "reason": "brief summary of what was accomplished"}

    Your goal is to orchestrate a COLLABORATIVE discussion where multiple
    agents each contribute their unique perspective. A good collaboration
    involves at least #{min_agents} different agents.

    Rules:
    1. Use the EXACT @callname from the members list below.
    2. Route to agents who have NOT yet responded before revisiting agents
       who already have. Each agent has a unique role — use them.
    3. When routing, explain in "reason" what you want this agent to add
       (e.g. "provide technical analysis", "offer a creative alternative").
    4. Only respond "__done__" when:
       - At least #{min_agents} different agents have contributed, AND
       - The user's request has been thoroughly addressed from multiple angles.
    5. When responding "__done__", summarize what the agents accomplished.
    6. Do NOT end after a single agent's response, even if it seems comprehensive.
       Other agents may have different perspectives, critiques, or additions.

    #{threshold_note}#{not_yet_list}

    Members:
    #{member_list}\
    """
  end

  # -------------------------------------------------------------------
  # Response parsing
  # -------------------------------------------------------------------

  @doc false
  def parse_routing_decision(content, routing_ctx) do
    members = routing_ctx.members
    responded = routing_ctx.responded
    min_agents = routing_ctx.min_agents
    enough_agents = MapSet.size(responded) >= min_agents

    text = normalize_content(content)

    case extract_json(text) do
      {:ok, %{"next" => "__done__"} = parsed} ->
        if enough_agents do
          {:done, Map.get(parsed, "reason", "Task complete.")}
        else
          # Override premature __done__ — pick an agent that hasn't responded yet
          Logger.info(
            "Coordinator tried __done__ with only #{MapSet.size(responded)}/#{min_agents} agents, overriding"
          )

          pick_unheard_agent(members, responded, nil)
        end

      {:ok, %{"next" => identifier} = parsed} ->
        reason = Map.get(parsed, "reason")
        resolve_agent(identifier, members, reason)

      {:error, _reason} ->
        extract_from_reasoning(text, members, enough_agents)
    end
  end

  # Normalizes Response content blocks into a plain text string.
  defp normalize_content(content) when is_binary(content), do: content
  defp normalize_content(nil), do: nil

  defp normalize_content(blocks) when is_list(blocks) do
    blocks
    |> Enum.filter(fn
      %{type: :text} -> true
      _ -> false
    end)
    |> Enum.map_join("\n", & &1.text)
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp normalize_content(_other), do: nil

  defp pick_unheard_agent(members, responded, reason) do
    case Enum.find(members, fn a -> not MapSet.member?(responded, a.callname) end) do
      nil -> fallback_to_first(members, reason)
      agent -> {:ok, agent, reason}
    end
  end

  defp resolve_agent(identifier, members, reason) do
    case find_agent_by_identifier(identifier, members) do
      nil ->
        # Try prefix match for truncated callnames (max_tokens may cut JSON mid-value)
        case find_agent_by_prefix(identifier, members) do
          nil ->
            Logger.warning(
              "Coordinator named unknown agent '#{identifier}', falling back to first member"
            )

            fallback_to_first(members, reason)

          agent ->
            Logger.debug("Coordinator prefix-matched '#{identifier}' to @#{agent.callname}")
            {:ok, agent, reason}
        end

      agent ->
        {:ok, agent, reason}
    end
  end

  defp find_agent_by_prefix(identifier, members) do
    cleaned = String.replace_leading(identifier, "@", "")
    lowered = String.downcase(cleaned)

    # Only match if prefix is at least 4 chars and matches exactly one agent
    if String.length(lowered) >= 4 do
      matches =
        Enum.filter(members, fn agent ->
          String.starts_with?(String.downcase(agent.callname), lowered) or
            String.starts_with?(String.downcase(agent.name), lowered)
        end)

      case matches do
        [single] -> single
        _ -> nil
      end
    else
      nil
    end
  end

  defp extract_json(content) when is_binary(content) do
    # Strip markdown code fences if present
    stripped =
      content
      |> String.replace(~r/```(?:json)?\s*/i, "")
      |> String.replace(~r/```/, "")
      |> String.trim()

    # Try to find a complete JSON object first
    case Regex.run(~r/\{.*\}/s, stripped) do
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> extract_next_field(stripped)
        end

      nil ->
        # JSON may be truncated (max_tokens cut it off) — try to extract "next" field
        extract_next_field(stripped)
    end
  end

  defp extract_json(_), do: {:error, :nil_content}

  # Extracts the "next" value from truncated JSON like {"next": "@callname", "reason": "...
  defp extract_next_field(text) do
    case Regex.run(~r/"next"\s*:\s*"([^"]+)"/, text) do
      [_, value] -> {:ok, %{"next" => value}}
      nil -> {:error, :no_json_found}
    end
  end

  # Scans plain-text reasoning for callnames or completion signals.
  # When enough agents have responded, done signals are accepted.
  defp extract_from_reasoning(content, members, enough_agents)
       when is_binary(content) do
    lowered = String.downcase(content)
    has_done = done_signal?(lowered)
    agent = find_agent_in_text(lowered, members)

    cond do
      enough_agents and has_done ->
        Logger.debug(
          "Coordinator reasoning contains done signal (enough agents responded), treating as :done"
        )

        {:done, "Request addressed."}

      agent != nil ->
        Logger.debug("Coordinator reasoning mentions @#{agent.callname}, routing to it")
        {:ok, agent, nil}

      has_done and not enough_agents ->
        Logger.debug("Coordinator reasoning has done signal but not enough agents, continuing")
        fallback_to_first(members, nil)

      has_done ->
        Logger.debug("Coordinator reasoning contains done signal, treating as :done")
        {:done, "Request addressed."}

      true ->
        Logger.warning(
          "Could not parse coordinator routing response, " <>
            "raw content: #{inspect(content)}, falling back to first member"
        )

        fallback_to_first(members, nil)
    end
  end

  defp extract_from_reasoning(_content, members, _enough_agents),
    do: fallback_to_first(members, nil)

  @done_patterns [
    "task is complete",
    "task is done",
    "task has been completed",
    "request has been addressed",
    "request has been fulfilled",
    "request is fulfilled",
    "no further action",
    "no more agents",
    "nothing more to add",
    "fully answered",
    "adequately addressed",
    "conversation is complete"
  ]

  defp done_signal?(lowered) do
    Enum.any?(@done_patterns, &String.contains?(lowered, &1))
  end

  # Find agent from reasoning text. Matches by @callname OR display name.
  # If multiple agents are mentioned, picks the LAST one mentioned
  # (reasoning models discuss options then state their decision last).
  # Returns nil only if NO agents are mentioned.
  defp find_agent_in_text(lowered, members) do
    # Find all agents mentioned and their last position in the text
    mentioned_with_pos =
      Enum.flat_map(members, fn agent ->
        callname_pos = last_position(lowered, "@#{String.downcase(agent.callname)}")
        name_pos = last_position(lowered, String.downcase(agent.name))
        pos = max(callname_pos, name_pos)

        if pos >= 0, do: [{agent, pos}], else: []
      end)

    case mentioned_with_pos do
      [] -> nil
      matches -> matches |> Enum.max_by(fn {_agent, pos} -> pos end) |> elem(0)
    end
  end

  defp last_position(haystack, needle) do
    case :binary.matches(haystack, needle) do
      [] -> -1
      matches -> matches |> List.last() |> elem(0)
    end
  end

  # Resolves an identifier to an agent. Supports:
  # - @callname (with or without @)
  # - Agent display name (case-insensitive)
  defp find_agent_by_identifier(identifier, members) do
    # Strip leading @ if present
    cleaned = String.replace_leading(identifier, "@", "")
    lowered = String.downcase(cleaned)

    Enum.find(members, fn agent ->
      String.downcase(agent.callname) == lowered or
        String.downcase(agent.name) == lowered
    end)
  end

  defp fallback_to_first([first | _], reason), do: {:ok, first, reason}
  defp fallback_to_first([], _reason), do: :done
end
