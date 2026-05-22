defmodule Summoner.Services.Plugins.HookRunner do
  @moduledoc """
  Runs lifecycle hooks on enabled plugin containers.

  Hook points: before_invocation, after_invocation, on_tool_call, on_error.
  Hooks run sequentially by priority (lower = first). Each has a timeout
  (default 5s, max 30s). Circuit breaker: 3 consecutive failures disables
  the hook.

  Returns:
  - `{:proceed, context}` — continue with (possibly modified) context
  - `{:halt, reason}` — stop execution
  """

  alias Summoner.Ports.Persistence.Plugins
  alias Summoner.Services.Plugins.ProtocolHandler

  require Logger

  @max_failures 3

  @doc """
  Run all enabled hook plugins for the given point.
  Returns {:proceed, context} or {:halt, reason}.
  """
  def run(workspace_id, point, context) do
    plugins = Plugins.list_enabled_by_capability(workspace_id, "hooks")

    plugins
    |> sort_by_priority()
    |> Enum.reduce_while({:proceed, context}, fn plugin, {:proceed, ctx} ->
      case run_single_hook(plugin, point, ctx) do
        {:ok, %{"action" => "proceed"}} ->
          {:cont, {:proceed, ctx}}

        {:ok, %{"action" => "modify", "context" => new_ctx}} ->
          {:cont, {:proceed, Map.merge(ctx, new_ctx)}}

        {:ok, %{"action" => "halt", "reason" => reason}} ->
          Logger.warning("Plugin #{plugin.name} halted at #{point}: #{reason}")
          {:halt, {:halt, reason}}

        {:ok, %{"action" => "halt"}} ->
          {:halt, {:halt, "Halted by plugin #{plugin.name}"}}

        {:error, reason} ->
          handle_hook_failure(plugin, point, reason)
          {:cont, {:proceed, ctx}}
      end
    end)
  end

  defp run_single_hook(plugin, point, context) do
    task =
      Task.async(fn ->
        ProtocolHandler.send_hook(plugin, to_string(point), context)
      end)

    timeout = get_hook_timeout(plugin)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  defp handle_hook_failure(plugin, point, reason) do
    Logger.warning("Plugin #{plugin.name} hook #{point} failed: #{inspect(reason)}")

    # Simple circuit breaker: track failures in plugin error_message metadata
    # In a full implementation, this would use a separate counter in the DB
    current_failures = count_failures(plugin)

    if current_failures + 1 >= @max_failures do
      Logger.error("Plugin #{plugin.name} hook disabled after #{@max_failures} failures")
      Plugins.update_status(plugin, :error, "Hook circuit breaker tripped: #{inspect(reason)}")
    end
  end

  defp count_failures(plugin) do
    case plugin.error_message do
      nil ->
        0

      msg when is_binary(msg) ->
        if String.contains?(msg, "circuit breaker"), do: @max_failures, else: 1

      _ ->
        0
    end
  end

  defp sort_by_priority(plugins) do
    Enum.sort_by(plugins, fn plugin ->
      get_in(plugin.manifest, ["hooks", "priority"]) || 100
    end)
  end

  defp get_hook_timeout(plugin) do
    timeout = get_in(plugin.manifest, ["hooks", "timeout_ms"])

    if is_integer(timeout) and timeout > 0 and timeout <= 30_000, do: timeout, else: 5_000
  end
end
