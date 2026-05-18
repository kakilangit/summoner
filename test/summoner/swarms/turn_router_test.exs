defmodule Summoner.Swarms.TurnRouterTest do
  use Summoner.DataCase

  alias Summoner.Swarms.Swarm
  alias Summoner.Swarms.TurnRouter

  # Build minimal agent structs for testing
  defp agent(name, id \\ nil) do
    %{id: id || Nulid.generate(), name: name, callname: String.downcase(name)}
  end

  describe "round_robin mode" do
    test "returns first member when no messages" do
      swarm = %Swarm{mode: :round_robin}
      a = agent("Alice")
      b = agent("Bob")

      assert {:ok, ^a} = TurnRouter.next_agent(swarm, [], [a, b])
    end

    test "returns first member after user message" do
      swarm = %Swarm{mode: :round_robin}
      a = agent("Alice")
      b = agent("Bob")

      messages = [%{role: :user, content: "hello", agent_id: nil}]
      assert {:ok, ^a} = TurnRouter.next_agent(swarm, messages, [a, b])
    end

    test "cycles to next member after agent response" do
      swarm = %Swarm{mode: :round_robin}
      a = agent("Alice", "id_a")
      b = agent("Bob", "id_b")

      messages = [
        %{role: :user, content: "hello", agent_id: nil},
        %{role: :assistant, content: "hi!", agent_id: "id_a"}
      ]

      assert {:ok, ^b} = TurnRouter.next_agent(swarm, messages, [a, b])
    end

    test "cycles back to first member after full cycle (continuous rotation)" do
      swarm = %Swarm{mode: :round_robin}
      a = agent("Alice", "id_a")
      b = agent("Bob", "id_b")

      messages = [
        %{role: :user, content: "hello", agent_id: nil},
        %{role: :assistant, content: "hi!", agent_id: "id_a"},
        %{role: :assistant, content: "hey!", agent_id: "id_b"}
      ]

      assert {:ok, ^a} = TurnRouter.next_agent(swarm, messages, [a, b])
    end

    test "returns :done with empty members" do
      swarm = %Swarm{mode: :round_robin}
      assert :done = TurnRouter.next_agent(swarm, [], [])
    end
  end

  describe "relay mode" do
    test "returns first member when no messages" do
      swarm = %Swarm{mode: :relay}
      a = agent("Alice")

      assert {:ok, ^a} = TurnRouter.next_agent(swarm, [], [a])
    end

    test "routes to first member on user message (regardless of content)" do
      swarm = %Swarm{mode: :relay}
      a = agent("Alice")
      b = agent("Bob")

      messages = [
        %{role: :user, content: "@bob do the thing", agent_id: nil}
      ]

      assert {:ok, ^a} = TurnRouter.next_agent(swarm, messages, [a, b])
    end

    test "routes to first member when user message has no mention" do
      swarm = %Swarm{mode: :relay}
      a = agent("Alice")
      b = agent("Bob")

      messages = [%{role: :user, content: "hello everyone", agent_id: nil}]
      assert {:ok, ^a} = TurnRouter.next_agent(swarm, messages, [a, b])
    end

    test "returns :done when last message is from assistant (routing via tool output)" do
      swarm = %Swarm{mode: :relay}
      a = agent("Alice", "id_a")
      b = agent("Bob")

      messages = [
        %{role: :user, content: "help", agent_id: nil},
        %{role: :assistant, content: "done!", agent_id: "id_a"}
      ]

      assert :done = TurnRouter.next_agent(swarm, messages, [a, b])
    end
  end

  describe "directed mode" do
    test "returns :done (routing handled externally)" do
      swarm = %Swarm{mode: :directed}
      a = agent("Alice")

      assert :done = TurnRouter.next_agent(swarm, [], [a])
    end
  end
end
