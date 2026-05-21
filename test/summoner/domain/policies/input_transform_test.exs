defmodule Summoner.Domain.Policies.InputTransformTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Policies.InputTransform

  describe "apply_transform/2" do
    test "returns body unchanged when transform is nil" do
      body = %{"foo" => "bar"}
      assert body == InputTransform.apply_transform(body, nil)
    end

    test "returns body unchanged when transform is empty string" do
      body = %{"foo" => "bar"}
      assert body == InputTransform.apply_transform(body, "")
    end

    test "interpolates template with body data" do
      body = %{"pull_request" => %{"title" => "Fix bug"}, "sender" => %{"login" => "alice"}}
      template = ~S|Review PR #{$.pull_request.title} by #{$.sender.login}|

      result = InputTransform.apply_transform(body, template)
      assert result["message"] == "Review PR Fix bug by alice"
    end

    test "handles missing paths gracefully" do
      body = %{"foo" => "bar"}
      template = ~S|Value: #{$.missing.path}|

      result = InputTransform.apply_transform(body, template)
      assert result["message"] == "Value: "
    end
  end

  describe "interpolate/2" do
    test "replaces multiple references" do
      data = %{"a" => "1", "b" => "2"}
      assert "1 and 2" == InputTransform.interpolate(~S|#{$.a} and #{$.b}|, data)
    end

    test "handles nested paths" do
      data = %{"x" => %{"y" => %{"z" => "deep"}}}
      assert "deep" == InputTransform.interpolate(~S|#{$.x.y.z}|, data)
    end
  end
end
