defmodule Summoner.Tenants.TenantSettings do
  @moduledoc """
  Schema for tenant settings — per-tenant configuration and limits.
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Tenants.Tenant

  schema "tenant_settings" do
    field :registration_mode, Ecto.Enum,
      values: [:disabled, :invitation, :open],
      default: :disabled

    field :max_workspaces, :integer, default: 10
    field :max_members, :integer, default: 50
    field :token_quota_monthly, :integer
    field :budget_usd_monthly, :decimal

    belongs_to :tenant, Tenant

    timestamps()
  end

  @doc """
  Changeset for creating or updating tenant settings.
  """
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :tenant_id,
      :registration_mode,
      :max_workspaces,
      :max_members,
      :token_quota_monthly,
      :budget_usd_monthly
    ])
    |> validate_required([:tenant_id, :registration_mode, :max_workspaces, :max_members])
    |> validate_inclusion(:registration_mode, [:disabled, :invitation, :open])
    |> validate_number(:max_workspaces, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:max_members, greater_than: 0, less_than_or_equal_to: 100_000)
    |> validate_number(:token_quota_monthly, greater_than: 0)
    |> validate_number(:budget_usd_monthly, greater_than: 0)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint(:tenant_id)
  end
end
