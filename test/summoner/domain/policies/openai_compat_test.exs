defmodule Summoner.Domain.Policies.OpenAICompatTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Policies.OpenAICompat

  describe "parse_model/1" do
    test "parses agent callname" do
      assert {:agent, "code_wizard"} = OpenAICompat.parse_model("summoner:code_wizard")
    end

    test "parses raw provider/model" do
      assert {:raw, "ollama", "qwen3:0.6b"} =
               OpenAICompat.parse_model("summoner:raw:ollama/qwen3:0.6b")
    end

    test "parses raw with complex model name" do
      assert {:raw, "copilot", "claude-sonnet-4-20250514"} =
               OpenAICompat.parse_model("summoner:raw:copilot/claude-sonnet-4-20250514")
    end

    test "rejects empty callname" do
      assert {:error, :invalid_model} = OpenAICompat.parse_model("summoner:")
    end

    test "rejects raw with missing model" do
      assert {:error, :invalid_model} = OpenAICompat.parse_model("summoner:raw:ollama/")
    end

    test "rejects raw with missing provider" do
      assert {:error, :invalid_model} = OpenAICompat.parse_model("summoner:raw:/model")
    end

    test "rejects non-summoner prefix" do
      assert {:error, :invalid_model} = OpenAICompat.parse_model("gpt-4o")
    end

    test "rejects nil" do
      assert {:error, :invalid_model} = OpenAICompat.parse_model(nil)
    end
  end

  describe "extract_input/1" do
    test "extracts last user message" do
      messages = [
        %{"role" => "system", "content" => "You are helpful"},
        %{"role" => "user", "content" => "Hello"},
        %{"role" => "assistant", "content" => "Hi"},
        %{"role" => "user", "content" => "What is 2+2?"}
      ]

      assert {:ok, "What is 2+2?"} = OpenAICompat.extract_input(messages)
    end

    test "returns error for no user message" do
      messages = [%{"role" => "system", "content" => "System only"}]
      assert {:error, :no_user_message} = OpenAICompat.extract_input(messages)
    end

    test "returns error for empty list" do
      assert {:error, :no_user_message} = OpenAICompat.extract_input([])
    end

    test "returns error for non-list" do
      assert {:error, :no_user_message} = OpenAICompat.extract_input("not a list")
    end
  end

  describe "format_completion/2" do
    test "formats successful invocation" do
      invocation = %{
        id: "test-id-123",
        output: %{"response" => "The answer is 4."},
        end_reason: :completed
      }

      result = OpenAICompat.format_completion(invocation, "summoner:math_agent")

      assert result["id"] == "chatcmpl-test-id-123"
      assert result["object"] == "chat.completion"
      assert result["model"] == "summoner:math_agent"
      assert [choice] = result["choices"]
      assert choice["message"]["role"] == "assistant"
      assert choice["message"]["content"] == "The answer is 4."
      assert choice["finish_reason"] == "stop"
    end

    test "maps token_limit_reached to length" do
      invocation = %{id: "x", output: %{"response" => ""}, end_reason: :token_limit_reached}
      result = OpenAICompat.format_completion(invocation, "m")
      assert hd(result["choices"])["finish_reason"] == "length"
    end

    test "handles nil output" do
      invocation = %{id: "x", output: nil, end_reason: :completed}
      result = OpenAICompat.format_completion(invocation, "m")
      assert hd(result["choices"])["message"]["content"] == ""
    end
  end

  describe "format_chunk/3" do
    test "formats content chunk" do
      chunk = OpenAICompat.format_chunk("inv-1", "summoner:bot", "Hello")
      assert chunk["object"] == "chat.completion.chunk"
      assert chunk["id"] == "chatcmpl-inv-1"
      assert hd(chunk["choices"])["delta"]["content"] == "Hello"
      assert hd(chunk["choices"])["finish_reason"] == nil
    end

    test "formats stop chunk" do
      chunk = OpenAICompat.format_chunk("inv-1", "summoner:bot", nil)
      assert hd(chunk["choices"])["delta"] == %{}
      assert hd(chunk["choices"])["finish_reason"] == "stop"
    end
  end

  describe "format_error/1" do
    test "formats error with defaults" do
      result = OpenAICompat.format_error("bad request")
      assert result["error"]["message"] == "bad request"
      assert result["error"]["type"] == "invalid_request_error"
    end

    test "formats error with custom type and code" do
      result = OpenAICompat.format_error("not found", "not_found_error", "model_not_found")
      assert result["error"]["code"] == "model_not_found"
    end
  end
end
