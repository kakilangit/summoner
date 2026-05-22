defmodule Summoner.Ports.ContainerRuntime do
  @moduledoc "Port for OCI container lifecycle operations."

  @adapter Application.compile_env(
             :summoner,
             :container_runtime_adapter,
             Summoner.Adapters.ContainerRuntime.Docker
           )

  @type container_opts :: %{
          image: String.t(),
          name: String.t(),
          env: %{String.t() => String.t()},
          network: boolean(),
          cpu: String.t(),
          memory: String.t()
        }

  @callback pull(String.t()) :: :ok | {:error, term()}
  @callback create(container_opts()) :: {:ok, String.t()} | {:error, term()}
  @callback start(String.t()) :: :ok | {:error, term()}
  @callback stop(String.t()) :: :ok | {:error, term()}
  @callback remove(String.t()) :: :ok | {:error, term()}
  @callback running?(String.t()) :: boolean()
  @callback logs(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  @callback inspect_container(String.t()) :: {:ok, map()} | {:error, term()}
  @callback extract_file(String.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  @callback stdio_transport_args(container_opts()) :: {command :: String.t(), args :: [String.t()]}

  defdelegate pull(image), to: @adapter
  defdelegate create(opts), to: @adapter
  defdelegate start(container_id), to: @adapter
  defdelegate stop(container_id), to: @adapter
  defdelegate remove(container_id), to: @adapter
  defdelegate running?(container_id), to: @adapter
  defdelegate logs(container_id, opts \\ []), to: @adapter
  defdelegate inspect_container(container_id), to: @adapter
  defdelegate extract_file(image, path), to: @adapter
  defdelegate stdio_transport_args(opts), to: @adapter
end
