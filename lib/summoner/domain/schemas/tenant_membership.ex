defmodule Summoner.Domain.Schemas.TenantMembership do
  @moduledoc """
  Schema for tenant memberships — user-to-tenant role assignments.

  Roles:
  - `:owner` — full control including ability to delete tenant; cannot be removed from their own tenant
  - `:admin` — tenant management (settings, members, shared resources, workspaces)
  - `:member` — belongs to this tenant, accesses workspaces via workspace memberships
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Tenant
  alias Summoner.Domain.Schemas.User

  @roles [:owner, :admin, :member]

  schema "tenant_memberships" do
    field :role, Ecto.Enum, values: @roles, default: :member

    belongs_to :tenant, Tenant
    belongs_to :user, User

    timestamps()
  end

  @doc "Returns the list of available roles."
  def roles, do: @roles

  @doc "Returns roles assignable by a tenant owner/admin (excludes :owner itself)."
  def assignable_roles, do: [:admin, :member]

  @doc """
  Changeset for creating or updating a tenant membership.
  """
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:tenant_id, :user_id, :role])
    |> validate_required([:tenant_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:tenant_id, :user_id])
  end
end
