defmodule Summoner.Domain.Schemas.AccessToken do
  @moduledoc """
  Schema for unified access tokens (Wards).

  Tokens authenticate API requests, A2A protocol, webhooks, OpenAI-compat,
  and MCP server endpoints. Each token has a set of scopes determining which
  endpoints it can access.

  Tokens are workspace-scoped and optionally linked to a user. They are hashed
  with Bcrypt; the plaintext is shown once at creation.

  ## Scopes

  - `"a2a"` — A2A protocol (Herald) authentication
  - `"api"` — REST API access
  - `"webhook"` — Webhook trigger authentication
  - `"openai"` — OpenAI-compatible API access
  - `"mcp"` — MCP server mode access
  - `"all"` — grants all scopes
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.User
  alias Summoner.Domain.Schemas.Workspace

  @valid_scopes ~w(a2a api webhook openai mcp all)

  schema "access_tokens" do
    field :label, :string
    field :token_hash, :string
    field :scopes, {:array, :string}, default: []
    field :last_used_at, :utc_datetime_usec
    field :request_count, :integer, default: 0
    field :revoked_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :rate_limit_rpm, :integer, default: 100

    # Virtual — plaintext shown once at creation
    field :token, :string, virtual: true

    belongs_to :workspace, Workspace
    belongs_to :user, User

    timestamps()
  end

  @cast_fields [:label, :token, :workspace_id, :user_id, :scopes, :expires_at, :rate_limit_rpm]
  @update_fields [:label, :scopes, :expires_at, :rate_limit_rpm]
  @required_fields [:label, :workspace_id]

  @doc """
  Changeset for creating a token. Generates and hashes automatically.
  """
  def create_changeset(token_record, attrs) do
    plaintext = generate_token()

    token_record
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_length(:label, min: 1, max: 100)
    |> validate_scopes()
    |> validate_number(:rate_limit_rpm, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_expires_at()
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:user_id)
    |> put_change(:token, plaintext)
    |> put_change(:token_hash, Bcrypt.hash_pwd_salt(plaintext))
  end

  @doc """
  Changeset for updating a token's mutable fields.
  """
  def update_changeset(token_record, attrs) do
    token_record
    |> cast(attrs, @update_fields)
    |> validate_required([:label])
    |> validate_length(:label, min: 1, max: 100)
    |> validate_scopes()
    |> validate_number(:rate_limit_rpm, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_expires_at()
  end

  @doc """
  Returns true if the token is active (not revoked and not expired).
  """
  def active?(%__MODULE__{revoked_at: nil, expires_at: nil}), do: true

  def active?(%__MODULE__{revoked_at: nil, expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :lt
  end

  def active?(_), do: false

  @doc """
  Returns true if the token has the given scope (or has "all").
  """
  def has_scope?(%__MODULE__{scopes: scopes}, required_scope) do
    "all" in scopes or required_scope in scopes
  end

  @doc """
  Returns the list of valid scope values.
  """
  def valid_scopes, do: @valid_scopes

  defp generate_token do
    "shk_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, &do_validate_scopes/2)
  end

  defp do_validate_scopes(:scopes, []), do: [scopes: "must have at least one scope"]

  defp do_validate_scopes(:scopes, scopes) do
    invalid = Enum.reject(scopes, &(&1 in @valid_scopes))

    if invalid == [] do
      []
    else
      [scopes: "invalid scopes: #{Enum.join(invalid, ", ")}"]
    end
  end

  defp validate_expires_at(changeset) do
    validate_change(changeset, :expires_at, fn :expires_at, expires_at ->
      if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
        []
      else
        [expires_at: "must be in the future"]
      end
    end)
  end
end
