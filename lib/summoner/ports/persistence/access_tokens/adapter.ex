defmodule Summoner.Ports.Persistence.AccessTokens.Adapter do
  @moduledoc "Behaviour for access token persistence operations."

  @callback list_tokens(String.t()) :: [struct()]
  @callback list_tokens(String.t(), keyword()) :: [struct()]
  @callback get_token!(String.t(), String.t()) :: struct()
  @callback create_token(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_token(struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback revoke_token(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback verify_token(String.t(), String.t()) :: {:ok, struct()} | {:error, :invalid}
  @callback verify_token(String.t(), String.t(), String.t()) ::
              {:ok, struct()} | {:error, :invalid | :wrong_scope | :expired}
end
