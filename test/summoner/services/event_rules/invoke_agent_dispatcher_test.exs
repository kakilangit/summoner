defmodule Summoner.Services.EventRules.InvokeAgentDispatcherTest do
  use ExUnit.Case, async: true

  alias Summoner.Services.EventRules.InvokeAgentDispatcher

  describe "interpolate/2" do
    test "replaces simple placeholders" do
      assert "Hello world" ==
               InvokeAgentDispatcher.interpolate("Hello {{name}}", %{"name" => "world"})
    end

    test "replaces nested placeholders" do
      data = %{"payload" => %{"status" => "completed"}}

      assert "Status: completed" ==
               InvokeAgentDispatcher.interpolate("Status: {{payload.status}}", data)
    end

    test "replaces multiple placeholders" do
      data = %{"agent" => "helper", "status" => "done"}

      assert "Agent helper is done" ==
               InvokeAgentDispatcher.interpolate("Agent {{agent}} is {{status}}", data)
    end

    test "missing field becomes empty string" do
      assert "Value: " == InvokeAgentDispatcher.interpolate("Value: {{missing}}", %{})
    end

    test "handles whitespace in placeholder" do
      assert "Hello world" ==
               InvokeAgentDispatcher.interpolate("Hello {{ name }}", %{"name" => "world"})
    end

    test "no placeholders returns template as-is" do
      assert "plain text" == InvokeAgentDispatcher.interpolate("plain text", %{})
    end
  end
end
