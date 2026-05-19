defmodule Summoner.Domain.Types.Pricing do
  @moduledoc """
  Token-to-USD cost estimation for known models.

  Prices are expressed as USD per 1 million tokens (prompt / completion).
  Models not in the table default to zero cost (free or unknown).

  ## Adding new models

  Add entries to `@prices` with the model identifier as key.
  Prefix-matching is used, so `"deepseek-v4"` matches
  `"deepseek-v4-flash"` and `"deepseek-v4-pro"`.
  """

  # Prices: {prompt_per_1m, completion_per_1m}
  # Source: provider pricing pages (as of 2026-05)
  @prices %{
    # DeepSeek
    "deepseek-v4-flash" => {0.10, 0.30},
    "deepseek-v4-pro" => {0.50, 1.50},
    "deepseek-chat" => {0.14, 0.28},
    "deepseek-reasoner" => {0.55, 2.19},
    # Z.AI / GLM
    "glm-4.5-air" => {0.00, 0.00},
    "glm-4-plus" => {0.50, 0.50},
    "glm-4-flash" => {0.00, 0.00},
    # OpenRouter free tier
    "openrouter/free" => {0.00, 0.00},
    # OpenAI (for reference)
    "gpt-4o" => {2.50, 10.00},
    "gpt-4o-mini" => {0.15, 0.60},
    "gpt-4.1" => {2.00, 8.00},
    "gpt-4.1-mini" => {0.40, 1.60},
    "gpt-4.1-nano" => {0.10, 0.40},
    # Anthropic (for reference)
    "claude-sonnet-4-20250514" => {3.00, 15.00},
    "claude-3-5-haiku-20241022" => {0.80, 4.00}
  }

  @doc """
  Estimates USD cost for a given model and token counts.

  Returns a `Decimal` value. Unknown models return `Decimal.new(0)`.
  """
  def estimate_cost(model, prompt_tokens, completion_tokens)
      when is_binary(model) and is_integer(prompt_tokens) and is_integer(completion_tokens) do
    {prompt_rate, completion_rate} = lookup_rate(model)

    prompt_cost = Decimal.mult(Decimal.new(prompt_tokens), rate_per_token(prompt_rate))

    completion_cost =
      Decimal.mult(Decimal.new(completion_tokens), rate_per_token(completion_rate))

    Decimal.add(prompt_cost, completion_cost)
  end

  @doc """
  Returns the pricing rate for a model as `{prompt_per_1m, completion_per_1m}`.

  Uses prefix matching — `"deepseek-v4-flash"` matches a `"deepseek-v4-flash"` key.
  Falls back to `{0.0, 0.0}` for unknown models.
  """
  def lookup_rate(model) when is_binary(model) do
    # Exact match first
    case Map.get(@prices, model) do
      nil -> prefix_match(model)
      rate -> rate
    end
  end

  defp prefix_match(model) do
    # Try matching by progressively shorter prefixes
    match =
      @prices
      |> Enum.find(fn {key, _rate} ->
        String.starts_with?(model, key) or String.starts_with?(key, model)
      end)

    case match do
      {_key, rate} -> rate
      nil -> {0.0, 0.0}
    end
  end

  # Convert per-1M rate to per-token rate as Decimal
  defp rate_per_token(rate) when is_float(rate) do
    Decimal.div(Decimal.from_float(rate), Decimal.new(1_000_000))
  end

  defp rate_per_token(rate) when is_integer(rate) do
    Decimal.div(Decimal.new(rate), Decimal.new(1_000_000))
  end
end
