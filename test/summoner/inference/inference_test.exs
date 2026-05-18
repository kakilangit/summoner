defmodule Summoner.InferenceTest do
  use ExUnit.Case, async: true

  alias Arcanum.Adapters.{Anthropic, Ollama, OpenAI}
  alias Summoner.Inference

  describe "adapter_for/1" do
    test "returns OpenAI adapter for openai api_format" do
      assert Inference.adapter_for(%{api_format: :openai}) == OpenAI
    end

    test "returns Anthropic adapter for anthropic api_format" do
      assert Inference.adapter_for(%{api_format: :anthropic}) == Anthropic
    end

    test "returns Ollama adapter for ollama kind" do
      assert Inference.adapter_for(%{kind: "ollama"}) == Ollama
    end

    test "returns OpenAI adapter for custom api_format fallback" do
      assert Inference.adapter_for(%{api_format: :custom}) == OpenAI
    end
  end
end
