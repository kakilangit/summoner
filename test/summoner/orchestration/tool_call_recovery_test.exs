defmodule Summoner.Orchestration.ToolCallRecoveryTest do
  use ExUnit.Case, async: true

  alias Arcanum.Response
  alias Summoner.Orchestration.ToolCallRecovery

  describe "recover/1" do
    test "passes through response with nil tool_calls" do
      response = %Response{content: nil, thinking: nil, tool_calls: nil, usage: nil}
      assert ToolCallRecovery.recover(response) == response
    end

    test "passes through response with empty tool_calls" do
      response = %Response{content: nil, thinking: nil, tool_calls: [], usage: nil}
      assert ToolCallRecovery.recover(response) == response
    end

    test "does not modify tool calls that already have names" do
      tool_calls = [
        %{id: "call_1", function: %{name: "__relay__", arguments: ~s({"next_agent": "sceptic"})}}
      ]

      response = %Response{content: nil, thinking: nil, tool_calls: tool_calls, usage: nil}
      assert ToolCallRecovery.recover(response) == response
    end

    test "recovers __relay__ from next_agent argument" do
      tool_calls = [
        %{id: "call_1", function: %{name: "__done__", arguments: ~s({"summary": "done"})}},
        %{id: nil, function: %{name: nil, arguments: ~s({"next_agent": "sceptic"})}}
      ]

      response = %Response{content: nil, thinking: nil, tool_calls: tool_calls, usage: nil}
      recovered = ToolCallRecovery.recover(response)

      assert [first, second] = recovered.tool_calls
      assert first.function.name == "__done__"
      assert second.function.name == "__relay__"
      assert second.function.arguments == ~s({"next_agent": "sceptic"})
      assert is_binary(second.id) and second.id != ""
    end

    test "recovers __done__ from summary argument" do
      tool_calls = [
        %{id: nil, function: %{name: nil, arguments: ~s({"summary": "All done"})}}
      ]

      response = %Response{content: nil, thinking: nil, tool_calls: tool_calls, usage: nil}
      recovered = ToolCallRecovery.recover(response)

      assert [tc] = recovered.tool_calls
      assert tc.function.name == "__done__"
      assert is_binary(tc.id)
    end

    test "does not recover __complete__ from result argument (too ambiguous)" do
      tool_calls = [
        %{id: nil, function: %{name: nil, arguments: ~s({"result": "final output"})}}
      ]

      response = %Response{content: nil, thinking: nil, tool_calls: tool_calls, usage: nil}
      recovered = ToolCallRecovery.recover(response)

      assert [tc] = recovered.tool_calls
      assert tc.function.name == nil
    end

    test "does not recover tool calls with unrecognized arguments" do
      tool_calls = [
        %{id: nil, function: %{name: nil, arguments: ~s({"query": "SELECT 1"})}}
      ]

      response = %Response{content: nil, thinking: nil, tool_calls: tool_calls, usage: nil}
      recovered = ToolCallRecovery.recover(response)

      assert [tc] = recovered.tool_calls
      assert tc.function.name == nil
    end

    test "does not recover tool calls with invalid JSON arguments" do
      tool_calls = [
        %{id: nil, function: %{name: nil, arguments: "not json"}}
      ]

      response = %Response{content: nil, thinking: nil, tool_calls: tool_calls, usage: nil}
      recovered = ToolCallRecovery.recover(response)

      assert [tc] = recovered.tool_calls
      assert tc.function.name == nil
    end

    test "preserves existing id when recovering" do
      tool_calls = [
        %{id: "existing_id", function: %{name: nil, arguments: ~s({"next_agent": "muse"})}}
      ]

      response = %Response{content: nil, thinking: nil, tool_calls: tool_calls, usage: nil}
      recovered = ToolCallRecovery.recover(response)

      assert [tc] = recovered.tool_calls
      assert tc.id == "existing_id"
      assert tc.function.name == "__relay__"
    end
  end
end
