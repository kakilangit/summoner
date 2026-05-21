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
  Verifies a plaintext token.

  ## Options

  - `:scope` — required scope the token must have (e.g. `"api"`)
  - `:workspace_id` — scope lookup to a specific workspace

  ## Examples

      verify_token(plaintext, scope: "api")
      verify_token(plaintext, scope: "a2a", workspace_id: ws_id)
      verify_token(plaintext, [])

  ## Returns

  - `{:ok, %AccessToken{}}` on success
  - `{:error, :invalid}` if no matching token
  - `{:error, :expired}` if token is expired
  - `{:error, :wrong_scope}` if token lacks required scope
  """
  @impl true
  def verify_token(plaintext, opts) do
    workspace_id = Keyword.get(opts, :workspace_id)
    required_scope = Keyword.get(opts, :scope)

    tokens = load_active_tokens(workspace_id)

    case Enum.find(tokens, fn t -> Bcrypt.verify_pass(plaintext, t.token_hash) end) do
      nil ->
        Bcrypt.no_user_verify()
        {:error, :invalid}

      %AccessToken{} = token ->
        validate_and_record(token, required_scope)
    end
  end

  defp validate_and_record(token, nil) do
    record_token_usage(token)
    {:ok, token}
  end

  defp validate_and_record(token, required_scope) do
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

  defp load_active_tokens(nil) do
    AccessToken
    |> where([t], is_nil(t.revoked_at))
    |> Repo.all()
  end

  defp load_active_tokens(workspace_id) do
    AccessToken
    |> where(workspace_id: ^workspace_id)
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
