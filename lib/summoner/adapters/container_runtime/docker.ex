defmodule Summoner.Adapters.ContainerRuntime.Docker do
  @moduledoc """
  Docker CLI adapter for OCI container lifecycle.

  Shells out to `docker` for pull, create, start, stop, rm, inspect, logs.
  Resource limits (CPU, memory) applied via `--cpus` and `--memory` flags.
  Network isolation via `--network none` when manifest declares `network: false`.
  """

  @behaviour Summoner.Ports.ContainerRuntime

  require Logger

  @docker_cmd "docker"
  @default_stop_timeout 10

  @impl true
  def pull(image) do
    case docker(["pull", image]) do
      {_, 0} -> :ok
      {output, code} -> {:error, "docker pull failed (exit #{code}): #{String.trim(output)}"}
    end
  end

  @impl true
  def create(opts) do
    args =
      ["create", "--name", opts.name] ++
        env_args(opts[:env] || %{}) ++
        resource_args(opts) ++
        network_args(opts) ++
        ["--label", "summoner.plugin=true"] ++
        [opts.image]

    case docker(args) do
      {container_id, 0} -> {:ok, String.trim(container_id)}
      {output, code} -> {:error, "docker create failed (exit #{code}): #{String.trim(output)}"}
    end
  end

  @impl true
  def start(container_id) do
    case docker(["start", container_id]) do
      {_, 0} -> :ok
      {output, code} -> {:error, "docker start failed (exit #{code}): #{String.trim(output)}"}
    end
  end

  @impl true
  def stop(container_id) do
    case docker(["stop", "-t", to_string(@default_stop_timeout), container_id]) do
      {_, 0} -> :ok
      {output, code} -> {:error, "docker stop failed (exit #{code}): #{String.trim(output)}"}
    end
  end

  @impl true
  def remove(container_id) do
    case docker(["rm", "-f", container_id]) do
      {_, 0} -> :ok
      {output, code} -> {:error, "docker rm failed (exit #{code}): #{String.trim(output)}"}
    end
  end

  @impl true
  def running?(container_id) do
    case docker(["inspect", "--format", "{{.State.Running}}", container_id]) do
      {"true\n", 0} -> true
      _ -> false
    end
  end

  @impl true
  def logs(container_id, opts \\ []) do
    tail = Keyword.get(opts, :tail, 100)
    args = ["logs", "--tail", to_string(tail), container_id]

    case docker(args) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, "docker logs failed (exit #{code}): #{String.trim(output)}"}
    end
  end

  @impl true
  def inspect_container(container_id) do
    case docker(["inspect", container_id]) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, [info | _]} -> {:ok, info}
          {:ok, []} -> {:error, :not_found}
          {:error, reason} -> {:error, reason}
        end

      {_, _code} ->
        {:error, :not_found}
    end
  end

  @impl true
  def extract_file(image, path) do
    temp_name = "summoner-extract-#{:erlang.unique_integer([:positive])}"

    with {_, 0} <- docker(["create", "--name", temp_name, image, "true"]),
         {output, 0} <-
           System.cmd(@docker_cmd, ["cp", "#{temp_name}:#{path}", "-"], stderr_to_stdout: true) do
      docker(["rm", "-f", temp_name])
      {:ok, output}
    else
      {output, _code} ->
        docker(["rm", "-f", temp_name])
        {:error, "extract failed: #{String.trim(output)}"}
    end
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp docker(args) do
    Logger.debug("docker #{Enum.join(args, " ")}")
    System.cmd(@docker_cmd, args, stderr_to_stdout: true)
  end

  defp env_args(env) when map_size(env) == 0, do: []

  defp env_args(env) do
    Enum.flat_map(env, fn {k, v} -> ["-e", "#{k}=#{v}"] end)
  end

  defp resource_args(opts) do
    args = []
    args = if opts[:cpu], do: args ++ ["--cpus", opts.cpu], else: args
    if opts[:memory], do: args ++ ["--memory", opts.memory], else: args
  end

  defp network_args(%{network: false}), do: ["--network", "none"]
  defp network_args(_opts), do: []
end
