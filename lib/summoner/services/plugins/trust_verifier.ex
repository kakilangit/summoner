defmodule Summoner.Services.Plugins.TrustVerifier do
  @moduledoc """
  Determines whether a plugin image is trusted based on registry allowlist.

  Trusted registries are loaded from `priv/plugins/trusted_registries.json`
  (default, shipped with release) or overridden via `PLUGIN_TRUSTED_REGISTRIES_PATH`.

  Untrusted plugins are forced to tenant isolation regardless of manifest.
  """

  require Logger

  @default_path "priv/plugins/trusted_registries.json"

  @doc "Check if an image is from a trusted registry."
  @spec trusted_image?(String.t()) :: boolean()
  def trusted_image?(image) do
    prefixes = load_trusted_prefixes()
    Enum.any?(prefixes, &String.starts_with?(image, &1))
  end

  @doc """
  Determine effective isolation for a plugin.

  Untrusted images are forced to `:tenant` regardless of manifest.
  """
  @spec effective_isolation(boolean(), String.t() | nil) :: :shared | :tenant
  def effective_isolation(trusted?, manifest_isolation) do
    cond do
      not trusted? -> :tenant
      manifest_isolation == "tenant" -> :tenant
      true -> :shared
    end
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp load_trusted_prefixes do
    path =
      System.get_env("PLUGIN_TRUSTED_REGISTRIES_PATH") ||
        Application.app_dir(:summoner, @default_path)

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"registries" => registries}} when is_list(registries) ->
            registries

          {:ok, _} ->
            Logger.warning("Invalid trusted_registries.json format at #{path}")
            []

          {:error, reason} ->
            Logger.warning("Failed to parse trusted_registries.json: #{inspect(reason)}")
            []
        end

      {:error, :enoent} ->
        Logger.debug("No trusted_registries.json found at #{path}, defaulting to empty")
        []

      {:error, reason} ->
        Logger.warning("Failed to read trusted_registries.json: #{inspect(reason)}")
        []
    end
  end
end
