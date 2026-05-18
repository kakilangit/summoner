defmodule Summoner.Swarms.SwarmCoordinatorTest do
  use ExUnit.Case, async: true

  alias Summoner.Swarms.SwarmCoordinator

  defp agent(name, callname),
    do: %{id: "id_#{callname}", name: name, callname: callname}

  defp members do
    [
      agent("Creative Muse", "creative_muse"),
      agent("Code Review", "code_review"),
      agent("Summarizer", "summarizer")
    ]
  end

  # Builds a routing context for parse_routing_decision/2.
  # `responded` is a list of callnames that have already responded.
  # `min_agents` defaults to 2.
  defp routing_ctx(opts \\ []) do
    responded = Keyword.get(opts, :responded, [])
    min_agents = Keyword.get(opts, :min_agents, 2)

    %{
      members: members(),
      responded: MapSet.new(responded),
      min_agents: min_agents
    }
  end

  describe "parse_routing_decision/2 — JSON parsing" do
    test "parses valid JSON with next agent by callname" do
      content = ~s({"next": "@creative_muse", "reason": "needs creative input"})

      assert {:ok, %{name: "Creative Muse"}, _} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end

    test "parses valid JSON with next agent by display name" do
      content = ~s({"next": "Creative Muse", "reason": "needs creative input"})

      assert {:ok, %{name: "Creative Muse"}, _} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end

    test "parses __done__ when enough agents responded" do
      content = ~s({"next": "__done__", "reason": "task complete"})

      ctx = routing_ctx(responded: ["creative_muse", "code_review"])

      assert {:done, "task complete"} =
               SwarmCoordinator.parse_routing_decision(content, ctx)
    end

    test "overrides __done__ when not enough agents responded" do
      content = ~s({"next": "__done__", "reason": "task complete"})

      ctx = routing_ctx(responded: ["creative_muse"])

      # Should pick an unheard agent instead of accepting __done__
      assert {:ok, agent, _} = SwarmCoordinator.parse_routing_decision(content, ctx)
      refute agent.callname == "creative_muse"
    end

    test "accepts __done__ when min_agents is 1 and one has responded" do
      content = ~s({"next": "__done__", "reason": "done"})

      ctx = routing_ctx(responded: ["creative_muse"], min_agents: 1)

      assert {:done, "done"} =
               SwarmCoordinator.parse_routing_decision(content, ctx)
    end

    test "parses JSON wrapped in markdown code fences" do
      content = "```json\n{\"next\": \"@summarizer\", \"reason\": \"wrap up\"}\n```"

      assert {:ok, %{name: "Summarizer"}, _} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end

    test "parses truncated JSON with next field" do
      content = ~s({"next": "@code_review", "reason": "the code needs)

      assert {:ok, %{name: "Code Review"}, _} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end

    test "JSON agent resolution is case-insensitive" do
      content = ~s({"next": "@Creative_Muse", "reason": "test"})

      assert {:ok, %{name: "Creative Muse"}, _} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end

    test "falls back when JSON names unknown agent" do
      content = ~s({"next": "@nonexistent", "reason": "test"})

      assert {:ok, %{name: "Creative Muse"}, _} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end

    test "handles nil content" do
      assert {:ok, %{name: "Creative Muse"}, _} =
               SwarmCoordinator.parse_routing_decision(nil, routing_ctx())
    end
  end

  describe "parse_routing_decision/2 — reasoning fallback (not enough agents)" do
    test "extracts agent from plain reasoning when only one callname mentioned" do
      content = "Based on the conversation, I think @creative_muse should respond next."

      assert {:ok, %{name: "Creative Muse"}, _} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end

    test "case-insensitive callname matching in reasoning" do
      content = "I recommend routing to @Creative_Muse for this task."

      assert {:ok, %{name: "Creative Muse"}, _} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end

    test "picks last-mentioned agent when multiple callnames in reasoning" do
      content =
        "@code_review could help but @creative_muse is the best choice for brainstorming."

      assert {:ok, %{name: "Creative Muse"}, _} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end

    test "routes to agent when reasoning mentions both agent and done signal" do
      content =
        ~s(we can set next to "__done__" but @creative_muse should answer first)

      assert {:ok, %{name: "Creative Muse"}, _} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end

    test "done signal without agents falls back to first member when not enough agents" do
      content = "The task is complete, no further agents needed."

      # With members and not enough responded, done signal is overridden
      assert {:ok, %{name: "Creative Muse"}, _} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end

    test "done signal without agents and empty members returns done" do
      content = "The task is complete, no further agents needed."

      ctx = %{members: [], responded: MapSet.new(), min_agents: 0}

      assert {:done, "Request addressed."} =
               SwarmCoordinator.parse_routing_decision(content, ctx)
    end

    test "falls back to first member when no signal found" do
      content = "I'm not sure what to do here, let me think about it carefully."

      assert {:ok, %{name: "Creative Muse"}, _} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end
  end

  describe "parse_routing_decision/2 — reasoning fallback (enough agents responded)" do
    defp enough_ctx do
      routing_ctx(responded: ["creative_muse", "code_review"])
    end

    test "done signal wins over agent mentions after enough agents responded" do
      content =
        "The assistant already answered. @creative_muse could add more but the task is complete."

      assert {:done, "Request addressed."} =
               SwarmCoordinator.parse_routing_decision(content, enough_ctx())
    end

    test "done signal wins even when model reasons about routing" do
      content =
        "We could route to @creative_muse for brainstorming but the request has been addressed. " <>
          "The assistant provided comprehensive project ideas."

      assert {:done, "Request addressed."} =
               SwarmCoordinator.parse_routing_decision(content, enough_ctx())
    end

    test "routes to agent when no done signal present" do
      content = "@creative_muse should add more creative ideas to complement the list."

      assert {:ok, %{name: "Creative Muse"}, _} =
               SwarmCoordinator.parse_routing_decision(content, enough_ctx())
    end

    test "falls back to first member when nothing matches" do
      content = "I'm not sure what to do here."

      assert {:ok, %{name: "Creative Muse"}, _} =
               SwarmCoordinator.parse_routing_decision(content, enough_ctx())
    end

    test "done signal patterns work" do
      for pattern <- [
            "The user's question has been fully answered",
            "The user's request has been addressed",
            "There is no further action needed",
            "The conversation is complete"
          ] do
        assert {:done, "Request addressed."} =
                 SwarmCoordinator.parse_routing_decision(
                   pattern <> " by @creative_muse.",
                   enough_ctx()
                 ),
               "Expected {:done, _} for pattern: #{pattern}"
      end
    end
  end

  describe "parse_routing_decision/2 — content block normalization" do
    test "handles list of content blocks (Response format)" do
      content = [%{type: :text, text: ~s({"next": "@code_review", "reason": "needs review"})}]

      assert {:ok, %{callname: "code_review"}, "needs review"} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end

    test "handles list with multiple text blocks" do
      content = [
        %{type: :text, text: ~s({"next": "@summarizer",)},
        %{type: :text, text: ~s( "reason": "wrap up"})}
      ]

      assert {:ok, %{callname: "summarizer"}, "wrap up"} =
               SwarmCoordinator.parse_routing_decision(content, routing_ctx())
    end

    test "handles nil content gracefully" do
      assert {:ok, %{callname: "creative_muse"}, nil} =
               SwarmCoordinator.parse_routing_decision(nil, routing_ctx())
    end
  end
end
