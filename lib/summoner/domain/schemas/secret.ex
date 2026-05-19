defmodule Summoner.Domain.Schemas.Secret do
  @moduledoc """
  Schema for workspace-scoped or tenant-scoped secrets (Seals).

  Values are encrypted at rest via `Summoner.Adapters.Crypto.EncryptedBinary`
  (Cloak AES-256-GCM). Secret names follow shell variable conventions
  (uppercase, underscores) and are referenced as `$SECRET_NAME` in
  MCP server configs.

  A secret belongs to exactly one of a workspace or a tenant (XOR).
  Tenant-scoped secrets are shared across all workspaces in the tenant.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  schema "secrets" do
    field :name, :string
    field :encrypted_value, Summoner.Adapters.Crypto.EncryptedBinary
    field :description, :string

    belongs_to :workspace, Summoner.Domain.Schemas.Workspace
    belongs_to :tenant, Summoner.Domain.Schemas.Tenant

    timestamps()
  end

  @cast_fields ~w(name encrypted_value workspace_id tenant_id description)a

  def changeset(secret, attrs) do
    secret
    |> cast(attrs, @cast_fields)
    |> validate_required([:name, :encrypted_value])
    |> validate_format(:name, ~r/^[A-Z][A-Z0-9_]*$/,
      message: "must be uppercase letters, digits, and underscores (e.g. GITHUB_TOKEN)"
    )
    |> validate_length(:name, min: 1, max: 255)
    |> validate_scope()
    |> unique_constraint([:workspace_id, :name],
      message: "a seal with this name already exists"
    )
    |> unique_constraint([:tenant_id, :name],
      message: "a seal with this name already exists"
    )
  end

  defp validate_scope(changeset) do
    tenant_id = get_field(changeset, :tenant_id)
    workspace_id = get_field(changeset, :workspace_id)

    cond do
      is_nil(tenant_id) and is_nil(workspace_id) ->
        add_error(changeset, :base, "must belong to either a tenant or a workspace")

      not is_nil(tenant_id) and not is_nil(workspace_id) ->
        add_error(changeset, :base, "cannot belong to both a tenant and a workspace")

      true ->
        changeset
    end
  end
end
