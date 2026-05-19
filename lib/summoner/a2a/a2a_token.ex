defmodule Summoner.A2A.A2AToken do
  @moduledoc """
  Schema for A2A access tokens.

  Tokens are scoped to a workspace — a valid token grants access to any
  protected Herald within that workspace. Tokens are hashed with Bcrypt;
  the plaintext is shown once at creation.
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Workspaces.Workspace

  schema "a2a_tokens" do
    field :label, :string
    field :token_hash, :string
    field :last_used_at, :utc_datetime_usec
    field :request_count, :integer, default: 0
    field :revoked_at, :utc_datetime_usec

    # Virtual — plaintext shown once at creation
    field :token, :string, virtual: true

    belongs_to :workspace, Workspace

    timestamps()
  end

  @cast_fields [:label, :token, :workspace_id]
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
    |> foreign_key_constraint(:workspace_id)
    |> put_change(:token, plaintext)
    |> put_change(:token_hash, Bcrypt.hash_pwd_salt(plaintext))
  end

  @doc """
  Returns true if the token is active (not revoked).
  """
  def active?(%__MODULE__{revoked_at: nil}), do: true
  def active?(_), do: false

  defp generate_token do
    "shk_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end
end
