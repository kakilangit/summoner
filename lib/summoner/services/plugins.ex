defmodule Summoner.Services.Plugins do
  @moduledoc """
  Service layer for plugin lifecycle management (Grimoires).

  Orchestrates install, enable, disable, configure, upgrade, uninstall
  flows. Uses digest-based shared containers and HTTP PluginClient.
  """

  alias Summoner.Adapters.Workers.PluginContainerManager
  alias Summoner.Domain.Policies.ManifestValidator
  alias Summoner.Domain.Schemas.PluginInstallation
  alias Summoner.Ports.ContainerRuntime
  alias Summoner.Ports.Persistence.Plugins, as: Persistence
  alias Summoner.Repo
  alias Summoner.Services.Plugins.PluginClient
  alias Summoner.Services.Plugins.TrustVerifier

  require Logger

  # -------------------------------------------------------------------
  # Boot
  # -------------------------------------------------------------------

  @doc "Start containers for all plugins in :enabled status. Called on application boot."
  def start_enabled_plugins do
    import Ecto.Query

    plugins =
      PluginInstallation
      |> where([p], p.status == :enabled)
      |> Repo.all()

    for plugin <- plugins do
      Logger.info("Booting enabled plugin: #{plugin.name} (#{plugin.ref})")

      case ensure_plugin_container(plugin) do
        {:ok, _container} ->
          Logger.info("Plugin #{plugin.name} started successfully")

        {:error, reason} ->
          Logger.error("Plugin #{plugin.name} failed to start: #{inspect(reason)}")
          Persistence.update_status(plugin, :error, "Boot failed: #{inspect(reason)}")
      end
    end

    :ok
  end

  # -------------------------------------------------------------------
  # CRUD (delegated to persistence port)
  # -------------------------------------------------------------------

  def get_plugin!(workspace_id, id), do: Persistence.get_plugin!(workspace_id, id)
  def get_plugin(workspace_id, id), do: Persistence.get_plugin(workspace_id, id)
  def get_plugin_by_ref!(workspace_id, ref), do: Persistence.get_plugin_by_ref!(workspace_id, ref)
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
  resolves digest, determines trust, creates the record (status: installed).
  """
  def install(workspace_id, image_ref) do
    with :ok <- ContainerRuntime.pull(image_ref),
         {:ok, manifest_json} <- extract_manifest(image_ref),
         {:ok, manifest} <- Jason.decode(manifest_json),
         {:ok, _validated} <- ManifestValidator.validate(manifest),
         {:ok, digest} <- ContainerRuntime.resolve_digest(image_ref) do
      trusted = TrustVerifier.trusted_image?(image_ref)

      attrs = %{
        name: manifest["name"],
        ref: PluginInstallation.compute_ref(image_ref),
        version: manifest["version"],
        capabilities: manifest["capabilities"],
        manifest: manifest,
        config: %{},
        status: :installed,
        digest: digest,
        trusted: trusted
      }

      Persistence.create_plugin(workspace_id, attrs)
    end
  end

  @doc """
  Enable a plugin: ensure shared container is running, register.
  """
  def enable(workspace_id, plugin_id) do
    plugin = Persistence.get_plugin!(workspace_id, plugin_id)

    if plugin.status in [:installed, :disabled, :error] do
      case ensure_plugin_container(plugin) do
        {:ok, _container} ->
          Persistence.update_status(plugin, :enabled)

        {:error, reason} ->
          Persistence.update_status(plugin, :error, "Enable failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, :already_enabled}
    end
  end

  @doc "Disable a plugin."
  def disable(workspace_id, plugin_id) do
    plugin = Persistence.get_plugin!(workspace_id, plugin_id)

    if plugin.status == :enabled do
      Persistence.update_status(plugin, :disabled)
    else
      {:error, :not_enabled}
    end
  end

  @doc "Update plugin configuration. No restart needed — config is per-request."
  def configure(workspace_id, plugin_id, config) do
    plugin = Persistence.get_plugin!(workspace_id, plugin_id)
    Persistence.update_plugin(plugin, %{config: config})
  end

  @doc "Upgrade plugin to new image version."
  def upgrade(workspace_id, plugin_id, new_image_ref) do
    plugin = Persistence.get_plugin!(workspace_id, plugin_id)
    was_enabled = plugin.status == :enabled

    with :ok <- ContainerRuntime.pull(new_image_ref),
         {:ok, manifest_json} <- extract_manifest(new_image_ref),
         {:ok, manifest} <- Jason.decode(manifest_json),
         {:ok, _validated} <- ManifestValidator.validate(manifest),
         {:ok, digest} <- ContainerRuntime.resolve_digest(new_image_ref) do
      trusted = TrustVerifier.trusted_image?(new_image_ref)

      {:ok, plugin} =
        Persistence.update_plugin(plugin, %{
          version: manifest["version"],
          manifest: manifest,
          status: :installed,
          error_message: nil,
          digest: digest,
          trusted: trusted
        })

      if was_enabled do
        enable(workspace_id, plugin.id)
      else
        {:ok, plugin}
      end
    end
  end

  @doc """
  Check if a newer version is available for a plugin.
  """
  def check_for_update(plugin) do
    latest_ref = latest_image_ref(plugin.manifest["image"])

    with :ok <- ContainerRuntime.pull(latest_ref),
         {:ok, manifest_json} <- extract_manifest(latest_ref),
         {:ok, manifest} <- Jason.decode(manifest_json) do
      if Version.compare(manifest["version"], plugin.version) == :gt do
        {:ok, %{version: manifest["version"], image: manifest["image"]}}
      else
        :up_to_date
      end
    end
  end

  @doc """
  Check and apply update in one step.
  """
  def update(workspace_id, plugin_id) do
    plugin = Persistence.get_plugin!(workspace_id, plugin_id)

    case check_for_update(plugin) do
      {:ok, %{image: new_image}} ->
        upgrade(workspace_id, plugin_id, new_image)

      :up_to_date ->
        :up_to_date

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Uninstall plugin completely."
  def uninstall(workspace_id, plugin_id) do
    plugin = Persistence.get_plugin!(workspace_id, plugin_id)
    Persistence.delete_plugin(plugin)
  end

  # -------------------------------------------------------------------
  # Webhook handling
  # -------------------------------------------------------------------

  @doc "Handle an inbound webhook for a plugin."
  def handle_webhook(workspace_id, plugin_id, route, headers, body) do
    case find_plugin(workspace_id, plugin_id) do
      nil ->
        {:error, :not_found}

      %{status: status} when status != :enabled ->
        {:error, :plugin_not_enabled}

      plugin ->
        with {:ok, container} <- get_plugin_container(plugin),
             context <- build_context(plugin, container) do
          PluginClient.send_webhook(container, context, route, headers, body)
        end
    end
  end

  @doc "Get logs from a plugin container."
  def get_logs(workspace_id, plugin_id, opts \\ []) do
    plugin = Persistence.get_plugin!(workspace_id, plugin_id)

    case get_plugin_container(plugin) do
      {:ok, container} -> ContainerRuntime.logs(container.container_name, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  # -------------------------------------------------------------------
  # Context (per-request config)
  # -------------------------------------------------------------------

  @doc "Build per-request context for a plugin."
  def build_context(plugin, container) do
    %{
      workspace_id: plugin.workspace_id,
      plugin_id: plugin.id,
      config: resolve_config(plugin),
      callback_url: internal_callback_url(),
      callback_token: container.callback_token
    }
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

  defp ensure_plugin_container(plugin) do
    image = plugin.manifest["image"]
    digest = plugin.digest

    isolation =
      TrustVerifier.effective_isolation(plugin.trusted, get_in(plugin.manifest, ["isolation"]))

    tenant_id = if isolation == :tenant, do: plugin.workspace_id, else: nil

    PluginContainerManager.ensure_container(image, digest, isolation, tenant_id)
  end

  defp get_plugin_container(plugin) do
    digest = plugin.digest

    isolation =
      TrustVerifier.effective_isolation(plugin.trusted, get_in(plugin.manifest, ["isolation"]))

    tenant_id = if isolation == :tenant, do: plugin.workspace_id, else: nil

    PluginContainerManager.get_container(digest, tenant_id)
  end

  defp resolve_config(plugin) do
    config_schema = get_in(plugin.manifest, ["config_schema", "properties"]) || %{}

    plugin.config
    |> Enum.into(%{}, fn {k, v} ->
      {k, resolve_config_value(config_schema, k, v)}
    end)
  end

  defp resolve_config_value(config_schema, key, value) do
    if get_in(config_schema, [key, "src"]) == "secret" do
      case Repo.get(Summoner.Domain.Schemas.Secret, value) do
        %{encrypted_value: decrypted} -> decrypted
        nil -> value
      end
    else
      value
    end
  end

  defp find_plugin(workspace_id, plugin_ref) do
    import Ecto.Query

    case Nulid.Ecto.cast(plugin_ref) do
      {:ok, _} ->
        Persistence.get_plugin(workspace_id, plugin_ref)

      :error ->
        Repo.one(
          from(p in PluginInstallation,
            where: p.workspace_id == ^workspace_id and p.ref == ^plugin_ref,
            limit: 1
          )
        )
    end
  end

  defp latest_image_ref(image) do
    image |> String.replace(~r/:[^\/]+$/, ":latest")
  end

  defp internal_callback_url do
    host = Application.get_env(:summoner, :plugin_callback_host, "host.docker.internal")
    port = System.get_env("PORT", "4000")
    "http://#{host}:#{port}/api/internal/plugins/callback"
  end
end
