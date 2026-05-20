defmodule Summoner.Ports.Persistence.Conversations.Adapter do
  @moduledoc "Behaviour for conversation persistence operations."

  # Conversations
  @callback create_conversation(map(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback create_system_conversation(map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_conversations(map(), String.t()) :: [struct()]
  @callback list_conversations_paginated(map(), String.t()) :: struct()
  @callback list_conversations_paginated(map(), String.t(), keyword()) :: struct()
  @callback get_conversation!(map(), String.t(), String.t()) :: struct()
  @callback update_primary_agent(map(), struct(), String.t()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_conversation(map(), struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_conversation(map(), struct()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}

  # Participants
  @callback add_participant(String.t(), String.t()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_participants(String.t()) :: [struct()]

  # Messages
  @callback add_message(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback soft_delete_message(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback restore_message(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback get_message!(String.t()) :: struct()
  @callback update_message_content(struct(), term()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_messages_after(struct()) :: {non_neg_integer(), nil}
  @callback list_messages(String.t()) :: [struct()]
  @callback list_messages(String.t(), keyword()) :: [struct()]
  @callback latest_summary(String.t()) :: struct() | nil
  @callback count_messages(String.t()) :: non_neg_integer()
  @callback mark_compacted([String.t()]) :: {non_neg_integer(), nil}

  # Export
  @callback export_as_markdown(String.t()) :: String.t()
  @callback export_as_markdown(String.t(), keyword()) :: String.t()
end
