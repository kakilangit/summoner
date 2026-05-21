defmodule Summoner.Ports.Persistence.AccessTokens.Adapter do
  @moduledoc """
  Behaviour for access token persistence operations.

  ## verify_token/2

  Single polymorphic verification function using keyword opts:

      verify_token(plaintext, scope: "api")                        # global
      verify_token(plaintext, scope: "api", workspace_id: ws_id)   # workspace-scoped
      verify_token(plaintext, [])                                  # global, no scope check
  """

  @callback list_tokens(String.t()) :: [struct()]
  @callback list_tokens(String.t(), keyword()) :: [struct()]
  @callback get_token!(String.t(), String.t()) :: struct()
  @callback create_token(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_token(struct(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback revoke_token(struct()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_token(struct()) :: {:ok, struct()} | {:error, :not_revoked}
  @callback verify_token(String.t(), keyword()) ::
              {:ok, struct()} | {:error, :invalid | :wrong_scope | :expired}
end
