defmodule Summoner.Inference.Adapters.OllamaTest do
  use ExUnit.Case, async: true

  import Mox

  alias Arcanum.Adapters.Ollama
  alias Arcanum.{Intent, ModelProfile, Response}
  alias Summoner.Ports.HTTPClientMock

  setup :verify_on_exit!

  @provider %{base_url: "http://localhost:11434"}

  describe "chat/2" do
    test "returns parsed response on success" do
      HTTPClientMock
      |> expect(:post, fn "http://localhost:11434/api/chat", _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             "message" => %{"content" => "Hello!", "role" => "assistant"},
             "done_reason" => "stop",
             "prompt_eval_count" => 10,
             "eval_count" => 5
           }
         }}
      end)

      intent = %Intent{messages: [%{role: "user", content: "Hi"}], model: "llama3"}

      assert {:ok, %Response{} = response} =
               Ollama.chat(@provider, intent, ModelProfile.default())

      assert response.content == Intent.text("Hello!")
      assert response.finish_reason == "stop"
      assert response.usage == %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
    end

    test "returns error on API failure" do
      HTTPClientMock
      |> expect(:post, fn _url, _opts ->
        {:ok, %{status: 500, body: %{"error" => "internal error"}}}
      end)

      intent = %Intent{messages: [%{role: "user", content: "Hi"}], model: "llama3"}

      assert {:error, {:api_error, 500, _}} =
               Ollama.chat(@provider, intent, ModelProfile.default())
    end

    test "returns error on network failure" do
      HTTPClientMock
      |> expect(:post, fn _url, _opts ->
        {:error, %Mint.TransportError{reason: :econnrefused}}
      end)

      intent = %Intent{messages: [%{role: "user", content: "Hi"}], model: "llama3"}

      assert {:error, %Mint.TransportError{}} =
               Ollama.chat(@provider, intent, ModelProfile.default())
    end

    test "includes tools in request body" do
      tools = [
        %{
          type: "function",
          function: %{
            name: "get_weather",
            description: "Get weather",
            parameters: %{type: "object", properties: %{}}
          }
        }
      ]

      HTTPClientMock
      |> expect(:post, fn _url, opts ->
        body = Keyword.get(opts, :json)
        assert body[:tools] == tools

        {:ok,
         %{
           status: 200,
           body: %{
             "message" => %{
               "content" => "",
               "tool_calls" => [
                 %{
                   "function" => %{
                     "name" => "get_weather",
                     "arguments" => %{"city" => "NYC"}
                   }
                 }
               ]
             },
             "done_reason" => "tool_calls"
           }
         }}
      end)

      intent = %Intent{
        messages: [%{role: "user", content: "Weather?"}],
        model: "llama3",
        tools: tools
      }

      assert {:ok, %Response{tool_calls: [tc]}} =
               Ollama.chat(@provider, intent, ModelProfile.default())

      assert tc.function.name == "get_weather"
      assert tc.function.arguments == ~s({"city":"NYC"})
    end
  end

  describe "list_models/1" do
    test "returns model names on success" do
      HTTPClientMock
      |> expect(:get, fn "http://localhost:11434/api/tags", _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             "models" => [
               %{"name" => "llama3:latest"},
               %{"name" => "codellama:7b"}
             ]
           }
         }}
      end)

      assert {:ok, models} = Ollama.list_models(@provider)
      assert models == ["llama3:latest", "codellama:7b"]
    end

    test "returns error on failure" do
      HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Ollama.list_models(@provider)
    end
  end
end
