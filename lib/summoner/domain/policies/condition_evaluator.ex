defmodule Summoner.Domain.Policies.ConditionEvaluator do
  @moduledoc """
  Pure function that evaluates a JSON condition DSL against an event payload.

  Supports combinators (`all`, `any`, `none`) and operators
  (`eq`, `neq`, `in`, `contains`, `gt`, `lt`, `gte`, `lte`, `exists`, `matches`).

  ## Examples

      iex> evaluate(%{"field" => "status", "op" => "eq", "value" => "completed"}, %{"status" => "completed"})
      true

      iex> evaluate(%{"all" => [%{"field" => "x", "op" => "gt", "value" => 5}]}, %{"x" => 10})
      true

      iex> evaluate(%{}, %{"anything" => true})
      true
  """

  @type condition :: map()
  @type payload :: map()

  @doc """
  Evaluates a condition against a payload. Returns true if the condition matches.

  An empty condition (`%{}`) always matches.
  """
  @spec evaluate(condition(), payload()) :: boolean()
  def evaluate(conditions, _payload) when conditions == %{}, do: true

  def evaluate(%{"all" => clauses}, payload) when is_list(clauses) do
    Enum.all?(clauses, &evaluate(&1, payload))
  end

  def evaluate(%{"any" => clauses}, payload) when is_list(clauses) do
    Enum.any?(clauses, &evaluate(&1, payload))
  end

  def evaluate(%{"none" => clauses}, payload) when is_list(clauses) do
    not Enum.any?(clauses, &evaluate(&1, payload))
  end

  def evaluate(%{"field" => field, "op" => op} = condition, payload) do
    actual = get_nested(payload, field)
    expected = Map.get(condition, "value")
    apply_op(op, actual, expected)
  end

  def evaluate(_invalid, _payload), do: false

  @spec get_nested(map(), String.t()) :: any()
  defp get_nested(data, path) when is_binary(path) do
    path
    |> String.split(".")
    |> Enum.reduce(data, fn
      key, %{} = acc -> Map.get(acc, key) || Map.get(acc, String.to_existing_atom(key))
      _key, _ -> nil
    end)
  rescue
    ArgumentError -> nil
  end

  @spec apply_op(String.t(), any(), any()) :: boolean()
  defp apply_op("eq", actual, expected), do: actual == expected
  defp apply_op("neq", actual, expected), do: actual != expected

  defp apply_op("in", actual, expected) when is_list(expected), do: actual in expected
  defp apply_op("in", _actual, _expected), do: false

  defp apply_op("contains", actual, expected) when is_binary(actual) and is_binary(expected) do
    String.contains?(actual, expected)
  end

  defp apply_op("contains", actual, expected) when is_list(actual), do: expected in actual
  defp apply_op("contains", _actual, _expected), do: false

  defp apply_op("gt", actual, expected) when is_number(actual) and is_number(expected) do
    actual > expected
  end

  defp apply_op("gt", _actual, _expected), do: false

  defp apply_op("lt", actual, expected) when is_number(actual) and is_number(expected) do
    actual < expected
  end

  defp apply_op("lt", _actual, _expected), do: false

  defp apply_op("gte", actual, expected) when is_number(actual) and is_number(expected) do
    actual >= expected
  end

  defp apply_op("gte", _actual, _expected), do: false

  defp apply_op("lte", actual, expected) when is_number(actual) and is_number(expected) do
    actual <= expected
  end

  defp apply_op("lte", _actual, _expected), do: false

  defp apply_op("exists", actual, true), do: not is_nil(actual)
  defp apply_op("exists", actual, false), do: is_nil(actual)
  defp apply_op("exists", actual, _), do: not is_nil(actual)

  defp apply_op("matches", actual, pattern) when is_binary(actual) and is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, actual)
      {:error, _} -> false
    end
  end

  defp apply_op("matches", _actual, _pattern), do: false

  defp apply_op(_unknown_op, _actual, _expected), do: false
end
