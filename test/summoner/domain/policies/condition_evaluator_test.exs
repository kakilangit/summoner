defmodule Summoner.Domain.Policies.ConditionEvaluatorTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Policies.ConditionEvaluator

  describe "evaluate/2" do
    test "empty conditions always match" do
      assert ConditionEvaluator.evaluate(%{}, %{"anything" => true})
    end

    test "eq operator" do
      cond = %{"field" => "status", "op" => "eq", "value" => "completed"}
      assert ConditionEvaluator.evaluate(cond, %{"status" => "completed"})
      refute ConditionEvaluator.evaluate(cond, %{"status" => "failed"})
    end

    test "neq operator" do
      cond = %{"field" => "status", "op" => "neq", "value" => "failed"}
      assert ConditionEvaluator.evaluate(cond, %{"status" => "completed"})
      refute ConditionEvaluator.evaluate(cond, %{"status" => "failed"})
    end

    test "in operator" do
      cond = %{"field" => "source", "op" => "in", "value" => ["api", "cli"]}
      assert ConditionEvaluator.evaluate(cond, %{"source" => "api"})
      assert ConditionEvaluator.evaluate(cond, %{"source" => "cli"})
      refute ConditionEvaluator.evaluate(cond, %{"source" => "web"})
    end

    test "in operator with non-list value returns false" do
      cond = %{"field" => "x", "op" => "in", "value" => "not_a_list"}
      refute ConditionEvaluator.evaluate(cond, %{"x" => "anything"})
    end

    test "contains operator on strings" do
      cond = %{"field" => "message", "op" => "contains", "value" => "error"}
      assert ConditionEvaluator.evaluate(cond, %{"message" => "fatal error occurred"})
      refute ConditionEvaluator.evaluate(cond, %{"message" => "all good"})
    end

    test "contains operator on lists" do
      cond = %{"field" => "tags", "op" => "contains", "value" => "urgent"}
      assert ConditionEvaluator.evaluate(cond, %{"tags" => ["urgent", "bug"]})
      refute ConditionEvaluator.evaluate(cond, %{"tags" => ["minor", "feature"]})
    end

    test "gt operator" do
      cond = %{"field" => "duration_ms", "op" => "gt", "value" => 5000}
      assert ConditionEvaluator.evaluate(cond, %{"duration_ms" => 6000})
      refute ConditionEvaluator.evaluate(cond, %{"duration_ms" => 5000})
      refute ConditionEvaluator.evaluate(cond, %{"duration_ms" => 4000})
    end

    test "lt operator" do
      cond = %{"field" => "score", "op" => "lt", "value" => 0.5}
      assert ConditionEvaluator.evaluate(cond, %{"score" => 0.3})
      refute ConditionEvaluator.evaluate(cond, %{"score" => 0.5})
    end

    test "gte operator" do
      cond = %{"field" => "count", "op" => "gte", "value" => 10}
      assert ConditionEvaluator.evaluate(cond, %{"count" => 10})
      assert ConditionEvaluator.evaluate(cond, %{"count" => 11})
      refute ConditionEvaluator.evaluate(cond, %{"count" => 9})
    end

    test "lte operator" do
      cond = %{"field" => "count", "op" => "lte", "value" => 10}
      assert ConditionEvaluator.evaluate(cond, %{"count" => 10})
      assert ConditionEvaluator.evaluate(cond, %{"count" => 9})
      refute ConditionEvaluator.evaluate(cond, %{"count" => 11})
    end

    test "exists operator (true)" do
      cond = %{"field" => "key", "op" => "exists", "value" => true}
      assert ConditionEvaluator.evaluate(cond, %{"key" => "present"})
      refute ConditionEvaluator.evaluate(cond, %{"other" => "value"})
    end

    test "exists operator (false)" do
      cond = %{"field" => "key", "op" => "exists", "value" => false}
      assert ConditionEvaluator.evaluate(cond, %{"other" => "value"})
      refute ConditionEvaluator.evaluate(cond, %{"key" => "present"})
    end

    test "matches operator" do
      cond = %{"field" => "code", "op" => "matches", "value" => "^err_"}
      assert ConditionEvaluator.evaluate(cond, %{"code" => "err_timeout"})
      refute ConditionEvaluator.evaluate(cond, %{"code" => "ok_done"})
    end

    test "matches with invalid regex returns false" do
      cond = %{"field" => "x", "op" => "matches", "value" => "[invalid"}
      refute ConditionEvaluator.evaluate(cond, %{"x" => "anything"})
    end

    test "unknown operator returns false" do
      cond = %{"field" => "x", "op" => "unknown", "value" => "y"}
      refute ConditionEvaluator.evaluate(cond, %{"x" => "y"})
    end

    test "numeric operators with non-numeric values return false" do
      for op <- ["gt", "lt", "gte", "lte"] do
        cond = %{"field" => "x", "op" => op, "value" => 5}
        refute ConditionEvaluator.evaluate(cond, %{"x" => "not_a_number"})
      end
    end
  end

  describe "nested field access" do
    test "dot-path access" do
      cond = %{"field" => "payload.status", "op" => "eq", "value" => "done"}
      assert ConditionEvaluator.evaluate(cond, %{"payload" => %{"status" => "done"}})
    end

    test "deeply nested access" do
      cond = %{"field" => "a.b.c", "op" => "eq", "value" => 42}
      assert ConditionEvaluator.evaluate(cond, %{"a" => %{"b" => %{"c" => 42}}})
    end

    test "missing nested field returns nil" do
      cond = %{"field" => "a.b.c", "op" => "exists", "value" => true}
      refute ConditionEvaluator.evaluate(cond, %{"a" => %{"x" => 1}})
    end
  end

  describe "combinators" do
    test "all combinator (AND)" do
      conditions = %{
        "all" => [
          %{"field" => "status", "op" => "eq", "value" => "completed"},
          %{"field" => "score", "op" => "gt", "value" => 0.8}
        ]
      }

      assert ConditionEvaluator.evaluate(conditions, %{"status" => "completed", "score" => 0.9})
      refute ConditionEvaluator.evaluate(conditions, %{"status" => "completed", "score" => 0.5})
      refute ConditionEvaluator.evaluate(conditions, %{"status" => "failed", "score" => 0.9})
    end

    test "any combinator (OR)" do
      conditions = %{
        "any" => [
          %{"field" => "source", "op" => "eq", "value" => "api"},
          %{"field" => "source", "op" => "eq", "value" => "cli"}
        ]
      }

      assert ConditionEvaluator.evaluate(conditions, %{"source" => "api"})
      assert ConditionEvaluator.evaluate(conditions, %{"source" => "cli"})
      refute ConditionEvaluator.evaluate(conditions, %{"source" => "web"})
    end

    test "none combinator (NOR)" do
      conditions = %{
        "none" => [
          %{"field" => "status", "op" => "eq", "value" => "failed"},
          %{"field" => "status", "op" => "eq", "value" => "cancelled"}
        ]
      }

      assert ConditionEvaluator.evaluate(conditions, %{"status" => "completed"})
      refute ConditionEvaluator.evaluate(conditions, %{"status" => "failed"})
      refute ConditionEvaluator.evaluate(conditions, %{"status" => "cancelled"})
    end

    test "nested combinators" do
      conditions = %{
        "all" => [
          %{"field" => "status", "op" => "eq", "value" => "completed"},
          %{
            "any" => [
              %{"field" => "source", "op" => "eq", "value" => "api"},
              %{"field" => "priority", "op" => "eq", "value" => "high"}
            ]
          }
        ]
      }

      assert ConditionEvaluator.evaluate(conditions, %{
               "status" => "completed",
               "source" => "api",
               "priority" => "low"
             })

      assert ConditionEvaluator.evaluate(conditions, %{
               "status" => "completed",
               "source" => "web",
               "priority" => "high"
             })

      refute ConditionEvaluator.evaluate(conditions, %{
               "status" => "failed",
               "source" => "api",
               "priority" => "high"
             })

      refute ConditionEvaluator.evaluate(conditions, %{
               "status" => "completed",
               "source" => "web",
               "priority" => "low"
             })
    end
  end

  describe "edge cases" do
    test "invalid condition shape returns false" do
      refute ConditionEvaluator.evaluate(%{"invalid" => "shape"}, %{})
    end

    test "nil payload field with eq" do
      cond = %{"field" => "missing", "op" => "eq", "value" => nil}
      assert ConditionEvaluator.evaluate(cond, %{"other" => "value"})
    end

    test "empty all combinator matches (vacuous truth)" do
      assert ConditionEvaluator.evaluate(%{"all" => []}, %{"x" => 1})
    end

    test "empty any combinator does not match" do
      refute ConditionEvaluator.evaluate(%{"any" => []}, %{"x" => 1})
    end

    test "empty none combinator matches" do
      assert ConditionEvaluator.evaluate(%{"none" => []}, %{"x" => 1})
    end
  end
end
