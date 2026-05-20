defmodule Summoner.Ports.Persistence.A2A.Adapter do
  @moduledoc "Behaviour for A2A persistence operations."

  # A2A Server (Herald) CRUD
  @callback list_servers(map(), String.t()) :: [struct()]
  @callback get_server!(map(), String.t(), String.t()) :: struct()
  @callback get_server_by_agent_id(String.t()) :: struct() | nil
  @callback get_server_with_agent!(String.t()) :: struct()
  @callback get_enabled_server_by_agent_id!(String.t()) :: struct()
  @callback create_server(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback create_server(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_server(map(), struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_server(struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_server(map(), struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_server(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback change_server(struct()) :: Ecto.Changeset.t()
  @callback change_server(struct(), map()) :: Ecto.Changeset.t()

  # A2A Token CRUD
  @callback list_tokens(String.t()) :: [struct()]
  @callback create_token(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback revoke_token(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback verify_token(String.t(), String.t()) :: {:ok, struct()} | {:error, :invalid}

  # A2A Task CRUD
  @callback get_task(String.t()) :: {:ok, struct()} | {:error, :not_found}
  @callback create_task(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_task(struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_tasks_by_context(String.t()) :: [struct()]
  @callback list_tasks_by_server(String.t()) :: [struct()]
  @callback list_tasks_by_server(String.t(), keyword()) :: [struct()]
  @callback get_task_conversation(String.t(), String.t()) :: {:ok, String.t()} | :not_found

  # Base URL
  @callback base_url(struct()) :: String.t()
end
