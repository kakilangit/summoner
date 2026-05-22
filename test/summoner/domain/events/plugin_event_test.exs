defmodule Summoner.Domain.Events.PluginEventTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Events.PluginEvent

  test "enforces required keys" do
    assert_raise ArgumentError, fn ->
      struct!(PluginEvent, %{})
    end
  end

  test "creates with all required fields" do
    event = %PluginEvent{
      plugin_id: "p1",
      plugin_name: "grimoire-test",
      event_name: "plugin.grimoire-test.pr_opened",
      data: %{"pr" => 42},
      workspace_id: "w1"
    }

    assert event.event_name == "plugin.grimoire-test.pr_opened"
    assert event.data == %{"pr" => 42}
  end

  test "all enforce_keys are present in struct" do
    fields = PluginEvent.__struct__() |> Map.keys() |> List.delete(:__struct__)
    assert :plugin_id in fields
    assert :plugin_name in fields
    assert :event_name in fields
    assert :data in fields
    assert :workspace_id in fields
  end
end
