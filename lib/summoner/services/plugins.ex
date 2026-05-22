defmodule Summoner.Services.Plugins do
  @moduledoc """
  Service layer for plugin lifecycle management (Grimoires).

  Orchestrates install, enable, disable, configure, upgrade, uninstall
  flows. Coordinates ContainerRuntime port, persistence port, and MCP
  connection.
  """

  alias Summoner.Adapters.Workers.PluginContainerManager
  alias Summoner.Domain.Policies.ManifestValidator
  alias Summoner.Domain.Schemas.PluginInstallation
  alias Summoner.Ports.ContainerRuntime
  alias Summoner.Ports.Persistence.Plugins, as: Persistence
  alias Summoner.Repo
  alias Summoner.Services.Plugins.ActionExecutor
  alias Summoner.Services.Plugins.ProtocolHandler

  require Logger

  # -------------------------------------------------------------------
  # CRUD (delegated to persistence port)
  # -------------------------------------------------------------------

  def get_plugin!(workspace_id, id), do: Persistence.get_plugin!(workspace_id, id)
  def get_plugin(workspace_id, id), do: Persistence.get_plugin(workspace_id, id)
  def list_plugins(workspace_id), do: Persistence.list_plugins(workspace_id)

  def list_plugins_paginated(workspace_id, opts \\ []),
    do: Persistence.list_plugins_paginated(workspace_id, opts)

  def delete_plugin(plugin), do: Persistence.delete_plugin(plugin)

  # -------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------

  @doc """
  Install a plugin from an OCI image reference.

  Pulls the image, extracts grimoire.json manifest, validates it,
  creates the plugin_installations record (status: installed).
  """
  def install(workspace_id, image_ref) do
    with :ok <- ContainerRuntime.pull(image_ref),
         {:ok, manifest_json} <- extract_manifest(image_ref),
         {:ok, manifest} <- Jason.decode(manifest_json),
         :ok <- ManifestValidator.validate(manifest) do
      attrs = %{
        name: manifest["name"],
        version: manifest["version"],
        capabilities: manifest["capabilities"],
        manifest: manifest,
        config: %{},
        status: :installed
      }

      Persistence.create_plugin(workspace_id, attrs)
    end
  end

  @doc """
  Enable a plugin: start container, connect MCP, validate capabilities,
  register resources.
  """
  def enable(workspace_id, plugin_id) do
    plugin = Persistence.get_plugin!(workspace_id, plugin_id)

    if plugin.status in [:installed, :disabled, :error] do
      case start_plugin_container(plugin) do
        :ok ->
          Persistence.update_status(plugin, :enabled)

        {:error, reason} ->
          Persistence.update_status(plugin, :error, "Enable failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, :already_enabled}
    end
  end

  @doc "Disable a plugin: stop container, unregister resources."
  def disable(workspace_id, plugin_id) do
    plugin = Persistence.get_plugin!(workspace_id, plugin_id)

    if plugin.status == :enabled do
      PluginContainerManager.stop_plugin(plugin.id)
      Persistence.update_status(plugin, :disabled)
    else
      {:error, :not_enabled}
    end
  end

  @doc "Update plugin configuration. Restarts if enabled."
  def configure(workspace_id, plugin_id, config) do
    plugin = Persistence.get_plugin!(workspace_id, plugin_id)

    with {:ok, plugin} <- Persistence.update_plugin(plugin, %{config: config}) do
      if plugin.status == :enabled do
        PluginContainerManager.stop_plugin(plugin.id)
        start_plugin_container(plugin)
      end

      {:ok, plugin}
    end
  end

  @doc "Upgrade plugin to new image version."
  def upgrade(workspace_id, plugin_id, new_image_ref) do
    plugin = Persistence.get_plugin!(workspace_id, plugin_id)
    was_enabled = plugin.status == :enabled

    # Disable if running
    if was_enabled do
      PluginContainerManager.stop_plugin(plugin.id)
    end

    with :ok <- ContainerRuntime.pull(new_image_ref),
         {:ok, manifest_json} <- extract_manifest(new_image_ref),
         {:ok, manifest} <- Jason.decode(manifest_json),
         :ok <- ManifestValidator.validate(manifest),
         {:ok, plugin} <-
           Persistence.update_plugin(plugin, %{
             version: manifest["version"],
             manifest: manifest,
             status: :installed,
             error_message: nil
           }) do
      if was_enabled do
        enable(workspace_id, plugin.id)
      else
        {:ok, plugin}
      end
    end
  end

  @doc "Uninstall plugin completely."
  def uninstall(workspace_id, plugin_id) do
    plugin = Persistence.get_plugin!(workspace_id, plugin_id)

    # Stop container if running
    if plugin.status == :enabled do
      PluginContainerManager.stop_plugin(plugin.id)
    end

    Persistence.delete_plugin(plugin)
  end

  # -------------------------------------------------------------------
  # Webhook handling
  # -------------------------------------------------------------------

  @doc "Handle an inbound webhook for a plugin."
  def handle_webhook(plugin_id, route, headers, body) do
    # Find plugin across all workspaces (webhook URL includes plugin_id)
    case find_plugin_by_id(plugin_id) do
      nil ->
        {:error, :not_found}

      %{status: status} when status != :enabled ->
        {:error, :plugin_not_enabled}

      plugin ->
        case ProtocolHandler.send_webhook(plugin, route, headers, body) do
          {:ok, %{"actions" => actions}} when is_list(actions) ->
            ActionExecutor.execute_actions(plugin, plugin.workspace_id, actions)
            {:ok, actions}

          {:ok, response} ->
            {:ok, response}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc "Get logs from a plugin container."
  def get_logs(workspace_id, plugin_id, opts \\ []) do
    plugin = Persistence.get_plugin!(workspace_id, plugin_id)
    container_name = "summoner-plugin-#{plugin.id}"
    ContainerRuntime.logs(container_name, opts)
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp extract_manifest(image_ref) do
    case ContainerRuntime.extract_file(image_ref, "/grimoire.json") do
      {:ok, content} -> {:ok, content}
      {:error, _} -> {:error, "No grimoire.json found in image"}
    end
  end

  defp start_plugin_container(plugin) do
    case DynamicSupervisor.start_child(
           Summoner.PluginSupervisor,
           {PluginContainerManager, plugin}
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_plugin_by_id(plugin_id) do
    # Query across all workspaces since webhook URL only has plugin_id
    Repo.get(PluginInstallation, plugin_id)
  end
end
