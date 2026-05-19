defmodule Summoner.Domain.Schemas.InvitationQuota do
  @moduledoc """
  Schema for invitation quotas — per-user, per-tenant invitation limits.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Tenant
  alias Summoner.Domain.Schemas.User

  schema "invitation_quotas" do
    field :amount, :integer, default: 0

    belongs_to :user, User
    belongs_to :tenant, Tenant

    timestamps()
  end

  @doc "Changeset for creating or updating a quota."
  def changeset(quota, attrs) do
    quota
    |> cast(attrs, [:user_id, :tenant_id, :amount])
    |> validate_required([:user_id, :amount])
    |> validate_number(:amount, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:user_id, :tenant_id],
      name: :invitation_quotas_user_id_tenant_id_index
    )
  end

  @doc "Changeset that adds the given amount to the existing quota."
  def add_changeset(quota, additional_amount)
      when is_integer(additional_amount) and additional_amount > 0 do
    new_amount = (quota.amount || 0) + additional_amount

    quota
    |> change(amount: new_amount)
    |> validate_number(:amount, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000)
  end

  @doc "Changeset that decrements quota by 1."
  def decrement_changeset(%__MODULE__{amount: amount} = quota) when amount > 0 do
    change(quota, amount: amount - 1)
  end

  def decrement_changeset(%__MODULE__{}) do
    {:error, :no_quota}
  end
end
