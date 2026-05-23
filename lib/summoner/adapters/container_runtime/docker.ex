defmodule Summoner.Adapters.ContainerRuntime.Docker do
  @moduledoc """
  Docker CLI adapter for OCI container lifecycle.

  Shells out to `docker` for pull, create, start, stop, rm, inspect, logs,
  run_detached (plugin HTTP containers), and resolve_digest.
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
         {tar_output, 0} <-
           System.cmd(@docker_cmd, ["cp", "#{temp_name}:#{path}", "-"], stderr_to_stdout: true) do
      docker(["rm", "-f", temp_name])
      extract_from_tar(tar_output)
    else
      {output, _code} ->
        docker(["rm", "-f", temp_name])
        {:error, "extract failed: #{String.trim(output)}"}
    end
  end

  @impl true
  def run_detached(opts) do
    port = opts[:port] || 9999

    publish_args =
      if opts[:publish_port], do: ["-p", "0:#{port}"], else: []

    args =
      ["run", "-d", "--name", opts.name, "--network", opts.network_name] ++
        publish_args ++
        env_args(opts[:env] || %{}) ++
        resource_args(opts) ++
        ["--label", "summoner.plugin=true"] ++
        [opts.image]

    case docker(args) do
      {container_id, 0} -> {:ok, String.trim(container_id)}
      {output, code} -> {:error, "docker run failed (exit #{code}): #{String.trim(output)}"}
    end
  end

  @impl true
  def host_port(container_id, container_port) do
    case docker([
           "inspect",
           "--format",
           "{{(index (index .NetworkSettings.Ports \"#{container_port}/tcp\") 0).HostPort}}",
           container_id
         ]) do
      {output, 0} ->
        case Integer.parse(String.trim(output)) do
          {port, _} -> {:ok, port}
          :error -> {:error, "invalid port: #{String.trim(output)}"}
        end

      {output, code} ->
        {:error, "docker inspect failed (exit #{code}): #{String.trim(output)}"}
    end
  end

  @impl true
  def ensure_network(name) do
    case docker(["network", "inspect", name]) do
      {_, 0} ->
        :ok

      _ ->
        case docker(["network", "create", name]) do
          {_, 0} ->
            :ok

          {output, code} ->
            {:error, "docker network create failed (exit #{code}): #{String.trim(output)}"}
        end
    end
  end

  @impl true
  def resolve_digest(image) do
    case docker(["inspect", "--format", "{{index .RepoDigests 0}}", image]) do
      {output, 0} ->
        digest =
          output
          |> String.trim()
          |> String.split("@")
          |> List.last()

        {:ok, digest}

      {_, _} ->
        # Fallback: compute digest from image ID
        case docker(["inspect", "--format", "{{.Id}}", image]) do
          {output, 0} ->
            {:ok, String.trim(output)}

          {output, code} ->
            {:error, "resolve_digest failed (exit #{code}): #{String.trim(output)}"}
        end
    end
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp extract_from_tar(tar_data) do
    case :erl_tar.extract({:binary, tar_data}, [:memory]) do
      {:ok, [{_name, content} | _]} -> {:ok, content}
      {:ok, []} -> {:error, "tar archive is empty"}
      {:error, reason} -> {:error, "tar extraction failed: #{inspect(reason)}"}
    end
  end

  defp docker(args) do
    Logger.debug("docker #{Enum.join(args, " ")}")
    System.cmd(@docker_cmd, args, stderr_to_stdout: true)
  rescue
    e in ErlangError ->
      case e.original do
        :enoent -> {"docker: command not found", 127}
        _ -> reraise e, __STACKTRACE__
      end
  end

  defp env_args(env) when map_size(env) == 0, do: []

  defp env_args(env) do
    Enum.flat_map(env, fn {k, v} -> ["-e", "#{k}=#{v}"] end)
  end

  defp resource_args(opts) do
    args = []
    args = if opts[:cpu], do: args ++ ["--cpus", opts.cpu], else: args
    if opts[:memory], do: args ++ ["--memory", normalize_memory(opts.memory)], else: args
  end

  defp normalize_memory(mem) when is_binary(mem) do
    mem
    |> String.replace(~r/([KMGT])i$/i, "\\1")
    |> String.downcase()
  end

  defp network_args(%{network: false}), do: ["--network", "none"]
  defp network_args(_opts), do: []
end
