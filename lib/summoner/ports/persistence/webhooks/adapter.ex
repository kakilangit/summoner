defmodule Summoner.Ports.Persistence.Webhooks.Adapter do
  @moduledoc "Behaviour for webhooks persistence operations."

  @callback create_webhook(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_webhook(map(), struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_webhook(map(), struct()) :: {:ok, struct()} | {:error, term()}
  @callback get_webhook!(map(), String.t(), String.t()) :: struct()
  @callback get_webhook(String.t()) :: struct() | nil
  @callback list_webhooks(map(), String.t(), keyword()) :: [struct()]
  @callback list_webhooks_paginated(map(), String.t(), keyword()) :: struct()
  @callback increment_trigger_count(String.t()) :: :ok
end
