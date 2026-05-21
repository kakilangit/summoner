defmodule Summoner.Domain.Schemas.EventRuleTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Schemas.EventRule

  describe "changeset/2" do
    test "valid changeset" do
      attrs = %{
        name: "test-rule",
        event_type: "invocation.completed",
        action_type: :invoke_agent,
        action_config: %{"agent_id" => "some-id"},
        workspace_id: "ws-id"
      }

      changeset = EventRule.changeset(%EventRule{}, attrs)
      assert changeset.valid?
    end

    test "requires name" do
      attrs = %{
        event_type: "invocation.completed",
        action_type: :invoke_agent,
        action_config: %{"agent_id" => "some-id"}
      }

      changeset = EventRule.changeset(%EventRule{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset, :name)
    end

    test "requires event_type" do
      attrs = %{
        name: "test",
        action_type: :invoke_agent,
        action_config: %{"agent_id" => "some-id"}
      }

      changeset = EventRule.changeset(%EventRule{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset, :event_type)
    end

    test "validates event_type inclusion" do
      attrs = %{
        name: "test",
        event_type: "invalid.type",
        action_type: :invoke_agent,
        action_config: %{"agent_id" => "some-id"}
      }

      changeset = EventRule.changeset(%EventRule{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset, :event_type)
    end

    test "validates invoke_agent requires agent_id or agent_callname" do
      attrs = %{
        name: "test",
        event_type: "invocation.completed",
        action_type: :invoke_agent,
        action_config: %{}
      }

      changeset = EventRule.changeset(%EventRule{}, attrs)
      refute changeset.valid?
      assert "requires agent_id or agent_callname" in errors_on(changeset, :action_config)
    end

    test "validates call_webhook requires url" do
      attrs = %{
        name: "test",
        event_type: "invocation.completed",
        action_type: :call_webhook,
        action_config: %{}
      }

      changeset = EventRule.changeset(%EventRule{}, attrs)
      refute changeset.valid?
      assert "requires url" in errors_on(changeset, :action_config)
    end

    test "validates run_pipeline requires pipeline_id" do
      attrs = %{
        name: "test",
        event_type: "invocation.completed",
        action_type: :run_pipeline,
        action_config: %{}
      }

      changeset = EventRule.changeset(%EventRule{}, attrs)
      refute changeset.valid?
      assert "requires pipeline_id" in errors_on(changeset, :action_config)
    end

    test "validates cooldown_s range" do
      attrs = %{
        name: "test",
        event_type: "invocation.completed",
        action_type: :send_notification,
        action_config: %{},
        cooldown_s: -1
      }

      changeset = EventRule.changeset(%EventRule{}, attrs)
      refute changeset.valid?
    end

    test "validates priority range" do
      attrs = %{
        name: "test",
        event_type: "invocation.completed",
        action_type: :send_notification,
        action_config: %{},
        priority: 1001
      }

      changeset = EventRule.changeset(%EventRule{}, attrs)
      refute changeset.valid?
    end

    test "send_notification accepts empty config" do
      attrs = %{
        name: "test",
        event_type: "invocation.completed",
        action_type: :send_notification,
        action_config: %{}
      }

      changeset = EventRule.changeset(%EventRule{}, attrs)
      assert changeset.valid?
    end
  end

  defp errors_on(changeset, field) do
    changeset.errors
    |> Keyword.get_values(field)
    |> Enum.map(fn {msg, _opts} -> msg end)
  end
end
