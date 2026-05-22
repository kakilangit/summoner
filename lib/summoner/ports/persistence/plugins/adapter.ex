defmodule Summoner.Ports.Persistence.Plugins.Adapter do
  @moduledoc "Behaviour for plugin persistence operations."

  @callback create_plugin(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback get_plugin!(String.t(), String.t()) :: struct()
  @callback get_plugin(String.t(), String.t()) :: struct() | nil
  @callback get_plugin_by_name(String.t(), String.t()) :: struct() | nil
  @callback list_plugins(String.t()) :: [struct()]
  @callback list_plugins_paginated(String.t(), keyword()) :: struct()
  @callback update_plugin(struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_status(struct(), atom(), String.t() | nil) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_plugin(struct()) :: {:ok, struct()} | {:error, term()}
  @callback list_enabled_by_capability(String.t(), String.t()) :: [struct()]
  @callback upsert_conversation(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback get_conversation_by_ref(String.t(), String.t()) :: struct() | nil

  # Plugin state
  @callback get_state(String.t(), String.t(), String.t()) :: struct() | nil
  @callback set_state(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_state(String.t(), String.t(), String.t()) :: :ok

  # Container support
  @callback enabled_digests() :: [String.t()]
end
