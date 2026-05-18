defmodule Summoner.Orchestration.McpToolExecutorTest do
  use Summoner.DataCase

  alias Summoner.Orchestration.McpToolExecutor

  describe "namespace_tool/2" do
    test "creates namespaced tool name" do
      assert McpToolExecutor.namespace_tool("my_server", "get_data") == "my_server__get_data"
    end

    test "sanitizes special characters in server name" do
      assert McpToolExecutor.namespace_tool("My Server!", "tool") == "My_Server___tool"
    end
  end

  describe "to_intent_tools/1" do
    test "converts MCP tools to Intent format" do
      mcp_tools = [
        %{
          server_id: "s1",
          server_name: "weather",
          tool: %{
            name: "get_forecast",
            description: "Get weather forecast",
            input_schema: %{
              "type" => "object",
              "properties" => %{
                "city" => %{"type" => "string"}
              }
            }
          }
        }
      ]

      [tool] = McpToolExecutor.to_intent_tools(mcp_tools)

      assert tool.type == "function"
      assert tool.function.name == "weather__get_forecast"
      assert tool.function.description == "Get weather forecast"
      assert tool.function.parameters["properties"]["city"]["type"] == "string"
    end

    test "handles tools without description or schema" do
      mcp_tools = [
        %{
          server_id: "s1",
          server_name: "db",
          tool: %{name: "ping", description: nil, input_schema: nil}
        }
      ]

      [tool] = McpToolExecutor.to_intent_tools(mcp_tools)

      assert tool.function.name == "db__ping"
      assert tool.function.description == ""

      assert tool.function.parameters == %{
               "type" => "object",
               "properties" => %{},
               "additionalProperties" => false
             }
    end

    test "returns empty list for no tools" do
      assert McpToolExecutor.to_intent_tools([]) == []
    end
  end

  describe "execute/2" do
    test "returns error for invalid tool name format" do
      tool_call = %{
        id: "tc1",
        function: %{name: "no_namespace", arguments: "{}"}
      }

      {:ok, id} = Nulid.generate()
      {:ok, wid} = Nulid.generate()

      assert {:error, msg} =
               McpToolExecutor.execute(tool_call, %{agent_id: id, workspace_id: wid})

      assert msg =~ "invalid tool name format"
    end

    test "returns error for empty parts in tool name" do
      tool_call = %{
        id: "tc1",
        function: %{name: "__tool", arguments: "{}"}
      }

      {:ok, id} = Nulid.generate()
      {:ok, wid} = Nulid.generate()

      assert {:error, msg} =
               McpToolExecutor.execute(tool_call, %{agent_id: id, workspace_id: wid})

      assert msg =~ "invalid tool name format"
    end

    test "returns error when server not equipped" do
      {:ok, agent_id} = Nulid.generate()
      {:ok, wid} = Nulid.generate()

      tool_call = %{
        id: "tc1",
        function: %{name: "nonexistent__tool", arguments: "{}"}
      }

      assert {:error, msg} =
               McpToolExecutor.execute(tool_call, %{agent_id: agent_id, workspace_id: wid})

      assert msg =~ "not equipped"
    end
  end
end
