defmodule Summoner.MCP.ClientBridge do
  @moduledoc """
  Bridge between Summoner MCP servers and the Anubis MCP client.

  Handles Summoner-specific concerns before delegating to Anubis:

  - Command allowlisting for stdio transport
  - Environment variable building with secret resolution
  - Connection lifecycle (start, stop, lookup)
  - Response normalization to match Summoner tool types

  Clients are registered via `Summoner.McpRegistry` keyed by
  `{context_workspace_id, server_id}` and started under
  `Summoner.McpSupervisor`. The `context_workspace_id` is the
  calling workspace's ID, enabling tenant-shared servers to have
  per-workspace client processes.
  """

  require Logger

  alias Summoner.MCP.McpServer
  alias Summoner.Secrets

  @allowed_executables ~w(npx uvx node python3 python docker docker-compose bash sh)
  @default_tool_timeout 120_000
  @ready_timeout 30_000

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc """
  Starts an MCP client for the given server if not already running.

  Returns `{:ok, client_pid}` or `{:error, reason}`.
  """
  def start_client(context_workspace_id, %McpServer{} = server) do
    key = {context_workspace_id, server.id}

    case Registry.lookup(Summoner.McpRegistry, key) do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid),
          do: {:ok, pid},
          else: do_start_client(context_workspace_id, server)

      [] ->
        do_start_client(context_workspace_id, server)
    end
  end

  @doc """
  Stops the MCP client for the given server if running.
  """
  def stop_client(context_workspace_id, %McpServer{} = server) do
    key = {context_workspace_id, server.id}

    case Registry.lookup(Summoner.McpRegistry, key) do
      [{client_pid, _}] when is_pid(client_pid) ->
        terminate_client_supervisor(client_pid)

      [] ->
        :ok
    end
  end

  @doc """
  Checks if an MCP client is currently running for the given server.
  """
  def client_running?(context_workspace_id, %McpServer{} = server) do
    key = {context_workspace_id, server.id}

    case Registry.lookup(Summoner.McpRegistry, key) do
      [{pid, _}] -> Process.alive?(pid)
      [] -> false
    end
  end

  @doc """
  Lists tools from an MCP server via Anubis.

  Returns `{:ok, [%{name, description, input_schema}]}` or `{:error, reason}`.
  """
  def list_tools(context_workspace_id, %McpServer{} = server) do
    with {:ok, client} <- ensure_client(context_workspace_id, server),
         {:ok, response} <- Anubis.Client.list_tools(client, timeout: @default_tool_timeout) do
      {:ok, normalize_tools(response.result)}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  @doc """
  Calls a tool on an MCP server via Anubis.

  Returns `{:ok, content_text}` or `{:error, reason}`.
  """
  def call_tool(context_workspace_id, %McpServer{} = server, tool_name, input) do
    timeout = tool_timeout(server)

    with {:ok, client} <- ensure_client(context_workspace_id, server),
         {:ok, response} <- Anubis.Client.call_tool(client, tool_name, input, timeout: timeout) do
      normalize_call_result(response)
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  # -------------------------------------------------------------------
  # Connection lifecycle
  # -------------------------------------------------------------------

  defp ensure_client(context_workspace_id, %McpServer{} = server) do
    key = {context_workspace_id, server.id}

    case Registry.lookup(Summoner.McpRegistry, key) do
      [{pid, _}] ->
        if Process.alive?(pid),
          do: {:ok, pid},
          else: do_start_client(context_workspace_id, server)

      [] ->
        do_start_client(context_workspace_id, server)
    end
  end

  defp do_start_client(context_workspace_id, %McpServer{} = server) do
    case build_anubis_opts(context_workspace_id, server) do
      {:ok, anubis_opts} ->
        start_child(context_workspace_id, server, anubis_opts)

      {:error, {:command_not_found, cmd}} ->
        Logger.warning("MCP server #{server.name}: command #{inspect(cmd)} not found, skipping")
        {:error, {:command_not_found, cmd}}

      {:error, reason} ->
        Logger.error("Failed to build MCP client options: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp start_child(context_workspace_id, server, anubis_opts) do
    case DynamicSupervisor.start_child(
           Summoner.McpSupervisor,
           {Summoner.MCP.ClientWrapper, {server, anubis_opts}}
         ) do
      {:ok, _sup_pid} ->
        await_client(context_workspace_id, server)

      {:error, {:already_started, _sup_pid}} ->
        await_client(context_workspace_id, server)

      {:error, reason} ->
        Logger.error("Failed to initialize MCP client: #{inspect(reason)}")
        {:error, {:connect_failed, reason}}
    end
  end

  defp await_client(context_workspace_id, %McpServer{} = server) do
    key = {context_workspace_id, server.id}

    case Registry.lookup(Summoner.McpRegistry, key) do
      [{pid, _}] ->
        case Anubis.Client.await_ready(pid, timeout: @ready_timeout) do
          :ok -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end

      [] ->
        {:error, :client_not_registered}
    end
  end

  # Finds the Anubis.Client.Supervisor that parents the client_pid
  # and terminates it via the McpSupervisor DynamicSupervisor.
  defp terminate_client_supervisor(client_pid) do
    sup_pid = find_parent_supervisor(client_pid)

    if sup_pid do
      DynamicSupervisor.terminate_child(Summoner.McpSupervisor, sup_pid)
    else
      :ok
    end
  end

  defp find_parent_supervisor(pid) do
    case Process.info(pid, :dictionary) do
      {_, dict} ->
        dict
        |> Keyword.get(:"$ancestors", [])
        |> List.first()

      nil ->
        nil
    end
  end

  # -------------------------------------------------------------------
  # Anubis option building
  # -------------------------------------------------------------------

  defp build_anubis_opts(context_workspace_id, %McpServer{} = server) do
    key = {context_workspace_id, server.id}
    transport_key = {context_workspace_id, server.id, :transport}

    case build_transport(context_workspace_id, server) do
      {:ok, transport} ->
        {:ok,
         [
           name: {:via, Registry, {Summoner.McpRegistry, key}},
           transport_name: {:via, Registry, {Summoner.McpRegistry, transport_key}},
           client_info: %{"name" => "Summoner", "version" => "0.1.0"},
           capabilities: %{},
           transport: transport
         ]}

      {:error, _reason} = error ->
        error
    end
  end

  defp build_transport(context_workspace_id, %McpServer{transport: :stdio} = server) do
    workspace_dir = Summoner.Workspaces.workspace_dir(context_workspace_id)

    case parse_command(server.command_or_url, server.config, workspace_dir) do
      {:ok, command, args} ->
        env = build_env(context_workspace_id, server, workspace_dir)
        {:ok, {:stdio, command: command, args: args, env: env, cwd: workspace_dir}}

      {:error, _reason} = error ->
        error
    end
  end

  defp build_transport(context_workspace_id, %McpServer{transport: :http} = server) do
    headers = build_headers_map(context_workspace_id, server)
    {:ok, {:streamable_http, base_url: server.command_or_url, headers: headers}}
  end

  # -------------------------------------------------------------------
  # Response normalization
  # -------------------------------------------------------------------

  defp normalize_tools(%{"tools" => tools}) when is_list(tools) do
    Enum.map(tools, fn tool ->
      %{
        name: tool["name"],
        description: tool["description"] || "",
        input_schema: tool["inputSchema"] || %{}
      }
    end)
  end

  defp normalize_tools(_), do: []

  defp normalize_call_result(%{is_error: true, result: result}) do
    {:error, extract_text(result["content"])}
  end

  defp normalize_call_result(%{result: result}) do
    {:ok, extract_text(result["content"])}
  end

  defp extract_text([%{"text" => text} | _]), do: text
  defp extract_text(content) when is_binary(content), do: content
  defp extract_text(nil), do: ""
  defp extract_text(content), do: Jason.encode!(content)

  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  # -------------------------------------------------------------------
  # Command parsing & security
  # -------------------------------------------------------------------

  defp parse_command(command_or_url, config, workspace_dir) do
    args = Map.get(config, "args", []) |> List.wrap()
    expanded = String.replace(command_or_url, "$WORKSPACE_DIR", workspace_dir)

    case String.split(expanded, " ", parts: 2) do
      [cmd] -> resolve_command(cmd, args)
      [cmd, rest] -> resolve_command(cmd, String.split(rest) ++ args)
    end
  end

  defp resolve_command(cmd, args) do
    base = Path.basename(cmd)

    unless base in @allowed_executables do
      raise ArgumentError,
            "Command #{inspect(cmd)} is not in the allowlist: #{inspect(@allowed_executables)}"
    end

    case System.find_executable(cmd) do
      nil -> {:error, {:command_not_found, cmd}}
      path -> {:ok, path, args}
    end
  end

  # -------------------------------------------------------------------
  # Environment building
  # -------------------------------------------------------------------

  defp build_env(context_workspace_id, server, workspace_dir) do
    raw_env =
      server.config
      |> Map.get("env", %{})
      |> Map.put_new("WORKSPACE_DIR", workspace_dir)

    case Secrets.resolve(context_workspace_id, server.tenant_id, raw_env) do
      {:ok, env} ->
        env

      {:error, {:missing_secrets, names}} ->
        Logger.warning(
          "MCP server #{server.name}: unresolved seal(s) #{inspect(names)}, passing raw values"
        )

        raw_env
    end
  end

  defp build_headers_map(context_workspace_id, server) do
    base = %{"content-type" => "application/json", "accept" => "application/json"}

    case Map.get(server.config, "api_key") do
      nil ->
        base

      key ->
        resolved =
          case Secrets.resolve_value(context_workspace_id, server.tenant_id, key) do
            {:ok, val} -> val
            {:error, _} -> key
          end

        Map.put(base, "authorization", "Bearer #{resolved}")
    end
  end

  defp tool_timeout(server) do
    case get_in(server.config, ["timeout_s"]) do
      s when is_integer(s) and s > 0 -> s * 1_000
      _ -> @default_tool_timeout
    end
  end
end
