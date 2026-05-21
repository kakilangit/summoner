defmodule Summoner.Adapters.Persistence.AccessTokens do
  @moduledoc """
  Ecto-backed persistence for access tokens (Wards).

  Handles CRUD, verification with scope checking, and usage tracking.
  """

  @behaviour Summoner.Ports.Persistence.AccessTokens.Adapter

  import Ecto.Query, warn: false

  alias Summoner.Domain.Schemas.AccessToken
  alias Summoner.Repo

  @doc """
  Lists all active tokens for a workspace.
  """
  @impl true
  def list_tokens(workspace_id, opts \\ []) do
    include_revoked = Keyword.get(opts, :include_revoked, false)

    AccessToken
    |> where(workspace_id: ^workspace_id)
    |> then(fn q ->
      if include_revoked, do: q, else: where(q, [t], is_nil(t.revoked_at))
    end)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single token by workspace and ID. Raises if not found.
  """
  @impl true
  def get_token!(workspace_id, id) do
    AccessToken
    |> where(workspace_id: ^workspace_id)
    |> Repo.get!(id)
  end

  @doc """
  Creates a new access token.

  Returns `{:ok, token}` where `token.token` contains the plaintext
  (shown once) or `{:error, changeset}`.
  """
  @impl true
  def create_token(attrs) do
    %AccessToken{}
    |> AccessToken.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing token's mutable fields (label, scopes, rate_limit_rpm, expires_at).
  """
  @impl true
  def update_token(%AccessToken{} = token, attrs) do
    token
    |> AccessToken.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Revokes a token by setting `revoked_at`.
  """
  @impl true
  def revoke_token(%AccessToken{} = token) do
    token
    |> Ecto.Changeset.change(%{revoked_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Verifies a plaintext token against stored hashes for a workspace.

  Returns `{:ok, %AccessToken{}}` if valid, `{:error, :invalid}` otherwise.
  Also increments request_count and updates last_used_at.
  """
  @impl true
  def verify_token(workspace_id, plaintext) do
    tokens = load_active_tokens(workspace_id)

    case Enum.find(tokens, fn t -> Bcrypt.verify_pass(plaintext, t.token_hash) end) do
      nil ->
        Bcrypt.no_user_verify()
        {:error, :invalid}

      %AccessToken{} = token ->
        record_token_usage(token)
        {:ok, token}
    end
  end

  @doc """
  Verifies a plaintext token with scope checking.

  Returns:
  - `{:ok, %AccessToken{}}` if valid and has required scope
  - `{:error, :invalid}` if token doesn't match
  - `{:error, :wrong_scope}` if token is valid but lacks required scope
  - `{:error, :expired}` if token is expired
  """
  @impl true
  def verify_token(workspace_id, plaintext, required_scope) do
    tokens = load_active_tokens(workspace_id)

    case Enum.find(tokens, fn t -> Bcrypt.verify_pass(plaintext, t.token_hash) end) do
      nil ->
        Bcrypt.no_user_verify()
        {:error, :invalid}

      %AccessToken{} = token ->
        cond do
          not AccessToken.active?(token) ->
            {:error, :expired}

          not AccessToken.has_scope?(token, required_scope) ->
            {:error, :wrong_scope}

          true ->
            record_token_usage(token)
            {:ok, token}
        end
    end
  end

  @doc """
  Verifies a plaintext token globally (no workspace filter).
  Used by API endpoints where workspace is derived from the token.
  """
  @impl true
  def verify_token_global(plaintext) do
    tokens = load_all_active_tokens()

    case Enum.find(tokens, fn t -> Bcrypt.verify_pass(plaintext, t.token_hash) end) do
      nil ->
        Bcrypt.no_user_verify()
        {:error, :invalid}

      %AccessToken{} = token ->
        record_token_usage(token)
        {:ok, token}
    end
  end

  @doc """
  Verifies a plaintext token globally with scope checking.
  """
  @impl true
  def verify_token_global(plaintext, required_scope) do
    tokens = load_all_active_tokens()

    case Enum.find(tokens, fn t -> Bcrypt.verify_pass(plaintext, t.token_hash) end) do
      nil ->
        Bcrypt.no_user_verify()
        {:error, :invalid}

      %AccessToken{} = token ->
        cond do
          not AccessToken.active?(token) ->
            {:error, :expired}

          not AccessToken.has_scope?(token, required_scope) ->
            {:error, :wrong_scope}

          true ->
            record_token_usage(token)
            {:ok, token}
        end
    end
  end

  defp load_active_tokens(workspace_id) do
    AccessToken
    |> where(workspace_id: ^workspace_id)
    |> where([t], is_nil(t.revoked_at))
    |> Repo.all()
  end

  defp load_all_active_tokens do
    AccessToken
    |> where([t], is_nil(t.revoked_at))
    |> Repo.all()
  end

  defp record_token_usage(%AccessToken{} = token) do
    AccessToken
    |> where(id: ^token.id)
    |> Repo.update_all(
      set: [last_used_at: DateTime.utc_now()],
      inc: [request_count: 1]
    )
  end
end
