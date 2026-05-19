defmodule Summoner.Domain.Schemas.Tenant do
  @moduledoc """
  Schema for tenants — the top-level organizational boundary.

  Every workspace belongs to exactly one tenant. Tenants group
  users, workspaces, and shared resources (providers, secrets, etc.).
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.{TenantMembership, TenantSettings}
  alias Summoner.Domain.Schemas.Workspace

  schema "tenants" do
    field :name, :string
    field :disabled_at, :utc_datetime_usec

    has_many :memberships, TenantMembership
    has_many :workspaces, Workspace
    has_one :settings, TenantSettings

    timestamps()
  end

  @doc """
  Changeset for creating or updating a tenant.
  """
  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :disabled_at])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:name)
  end
end
