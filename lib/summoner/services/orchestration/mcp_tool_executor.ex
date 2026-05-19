defmodule Summoner.Services.Orchestration.McpToolExecutor do
  @moduledoc """
  Concrete `ToolExecutor` implementation backed by the MCP bridge.

  Maps LLM tool calls to MCP server tool invocations, enforcing the
  agent's Magic Circle allowlist.

  ## Tool naming

  Tools are namespaced as `"server_name__tool_name"` to avoid collisions
  when an agent has multiple MCP servers equipped. The executor splits
  the name, looks up the server, and calls the tool via `MCP.call_tool/4`.
  """

  @behaviour Summoner.Services.Orchestration.ToolExecutor

  alias Summoner.Adapters.Persistence.MCP

  @impl true
  def execute(tool_call, %{agent_id: agent_id, workspace_id: workspace_id}) do
    full_name = tool_call.function.name
    servers = MCP.list_equipped_servers(agent_id)

    with {:ok, server_name, tool_name} <- split_tool_name(full_name, servers),
         {:ok, server} <- find_equipped_server(servers, server_name),
         {:ok, input} <- parse_arguments(tool_call.function.arguments) do
      MCP.call_tool(workspace_id, server, tool_name, input)
    end
  end

  @doc """
  Converts MCP tool descriptors into OpenAI-format tool definitions
  for the Intent struct. Namespaces tool names with the server name.

  Accepts the output of `MCP.list_tools_for_agent/2`.
  """
  def to_intent_tools(mcp_tools) do
    Enum.map(mcp_tools, fn %{server_name: server_name, tool: tool} ->
      %{
        type: "function",
        function: %{
          name: namespace_tool(server_name, tool.name),
          description: tool.description || "",
          parameters: tool.input_schema |> sanitize_schema() |> enforce_object_schema()
        }
      }
    end)
  end

  @doc """
  Creates a namespaced tool name from server name and tool name.
  """
  def namespace_tool(server_name, tool_name) do
    sanitized = server_name |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    "#{sanitized}__#{tool_name}"
  end

  defp split_tool_name(full_name, servers) do
    cleaned = sanitize_tool_call_name(full_name)

    case String.split(cleaned, "__", parts: 2) do
      [server_name, tool_name] when server_name != "" and tool_name != "" ->
        {:ok, server_name, tool_name}

      _ ->
        split_tool_name_fuzzy(cleaned, servers)
    end
  end

  # Strip LLM hallucinated tokens like <|channel|>, <|end|>, etc. and trailing
  # non-identifier characters that some models append to tool names.
  defp sanitize_tool_call_name(nil), do: ""

  defp sanitize_tool_call_name(name) do
    name
    |> String.replace(~r/<\|[^|]*\|>.*/, "")
    |> String.trim_trailing()
  end

  defp split_tool_name_fuzzy(full_name, servers) do
    sanitized_names = Enum.map(servers, &sanitize_name(&1.name))

    match =
      Enum.find_value(sanitized_names, fn server_name ->
        prefix = server_name <> "_"
        try_prefix_match(full_name, prefix, server_name)
      end)

    case match do
      {server_name, tool_name} -> {:ok, server_name, tool_name}
      nil -> {:error, "invalid tool name format: #{full_name}, expected server__tool"}
    end
  end

  defp try_prefix_match(full_name, prefix, server_name) do
    if String.starts_with?(full_name, prefix) do
      tool_name = String.replace_leading(full_name, prefix, "")
      if tool_name != "", do: {server_name, tool_name}
    end
  end

  defp find_equipped_server(servers, server_name) do
    # Exact match first, then case-insensitive fallback
    match =
      Enum.find(servers, fn s -> sanitize_name(s.name) == server_name end) ||
        Enum.find(servers, fn s ->
          String.downcase(sanitize_name(s.name)) == String.downcase(server_name)
        end)

    case match do
      nil -> {:error, "MCP server '#{server_name}' not equipped to this agent"}
      server -> {:ok, server}
    end
  end

  defp sanitize_name(name), do: String.replace(name, ~r/[^a-zA-Z0-9_]/, "_")

  # Enforce object type and disallow additional properties on tool input schemas.
  # Some models struggle with non-object schemas or schemas that allow extra fields.
  defp enforce_object_schema(schema) when is_map(schema) do
    schema
    |> Map.put("type", "object")
    |> Map.put("additionalProperties", false)
  end

  defp enforce_object_schema(schema), do: schema

  defp parse_arguments(""), do: {:ok, %{}}

  defp parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, "invalid tool arguments JSON: #{args}"}
    end
  end

  defp parse_arguments(args) when is_map(args), do: {:ok, args}
  defp parse_arguments(_), do: {:ok, %{}}

  # Recursively strip nil values from tool schemas so that local provider
  # Jinja prompt templates don't choke on NullValue.
  defp sanitize_schema(nil), do: %{"type" => "object", "properties" => %{}}

  defp sanitize_schema(schema) when is_map(schema) do
    schema
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new(fn {k, v} -> {k, sanitize_schema_value(v)} end)
  end

  defp sanitize_schema(other), do: other

  defp sanitize_schema_value(v) when is_map(v), do: sanitize_schema(v)
  defp sanitize_schema_value(v) when is_list(v), do: Enum.map(v, &sanitize_schema_value/1)
  defp sanitize_schema_value(v), do: v
end
