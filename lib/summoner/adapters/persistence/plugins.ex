defmodule Summoner.Adapters.Persistence.Plugins do
  @moduledoc """
  Persistence adapter for plugin installations (Grimoires) and
  plugin conversation mappings.
  """

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Pagination
  alias Summoner.Domain.Schemas.{PluginConversation, PluginInstallation, PluginState}
  alias Summoner.Repo

  @behaviour Summoner.Ports.Persistence.Plugins.Adapter

  # -------------------------------------------------------------------
  # Plugin Installations
  # -------------------------------------------------------------------

  def create_plugin(workspace_id, attrs) do
    %PluginInstallation{}
    |> PluginInstallation.changeset(Map.put(attrs, :workspace_id, workspace_id))
    |> Repo.insert()
  end

  def get_plugin!(workspace_id, id) do
    PluginInstallation
    |> where([p], p.workspace_id == ^workspace_id)
    |> Repo.get!(id)
  end

  def get_plugin(workspace_id, id) do
    PluginInstallation
    |> where([p], p.workspace_id == ^workspace_id)
    |> Repo.get(id)
  end

  def get_plugin_by_name(workspace_id, name) do
    Repo.get_by(PluginInstallation, workspace_id: workspace_id, name: name)
  end

  def get_plugin_by_ref!(workspace_id, ref) do
    PluginInstallation
    |> where([p], p.workspace_id == ^workspace_id and p.ref == ^ref)
    |> Repo.one!()
  end

  def list_plugins(workspace_id) do
    PluginInstallation
    |> where([p], p.workspace_id == ^workspace_id)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  def list_plugins_paginated(workspace_id, opts \\ []) do
    PluginInstallation
    |> where([p], p.workspace_id == ^workspace_id)
    |> Pagination.paginate(opts)
  end

  def update_plugin(%PluginInstallation{} = plugin, attrs) do
    plugin
    |> PluginInstallation.changeset(attrs)
    |> Repo.update()
  end

  def update_status(%PluginInstallation{} = plugin, status, error_message \\ nil) do
    plugin
    |> PluginInstallation.status_changeset(status, error_message)
    |> Repo.update()
  end

  def delete_plugin(%PluginInstallation{} = plugin) do
    Repo.delete(plugin)
  end

  def list_enabled_by_capability(workspace_id, capability) do
    PluginInstallation
    |> where(
      [p],
      p.workspace_id == ^workspace_id and p.status == :enabled and ^capability in p.capabilities
    )
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Plugin Conversations
  # -------------------------------------------------------------------

  def upsert_conversation(attrs) do
    %PluginConversation{}
    |> PluginConversation.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:conversation_id, :updated_at]},
      conflict_target: [:plugin_id, :external_ref]
    )
  end

  def get_conversation_by_ref(plugin_id, external_ref) do
    Repo.get_by(PluginConversation,
      plugin_id: plugin_id,
      external_ref: external_ref
    )
  end

  def get_conversation_by_id(plugin_id, conversation_id) do
    Repo.get_by(PluginConversation,
      plugin_id: plugin_id,
      conversation_id: conversation_id
    )
  end

  # -------------------------------------------------------------------
  # Plugin State
  # -------------------------------------------------------------------

  def get_state(workspace_id, plugin_id, key) do
    Repo.get_by(PluginState,
      workspace_id: workspace_id,
      plugin_id: plugin_id,
      key: key
    )
  end

  def set_state(attrs) do
    %PluginState{}
    |> PluginState.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: [:workspace_id, :plugin_id, :key]
    )
  end

  def delete_state(workspace_id, plugin_id, key) do
    PluginState
    |> where(
      [s],
      s.workspace_id == ^workspace_id and s.plugin_id == ^plugin_id and s.key == ^key
    )
    |> Repo.delete_all()

    :ok
  end

  # -------------------------------------------------------------------
  # Container support
  # -------------------------------------------------------------------

  def enabled_digests do
    PluginInstallation
    |> where([p], p.status == :enabled)
    |> select([p], p.digest)
    |> distinct(true)
    |> Repo.all()
  end
end
