defmodule Summoner.Invitations.Invitation do
  @moduledoc """
  Schema for invitation codes — single-use, 30-day expiry, platform or tenant scoped.
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Accounts.User
  alias Summoner.Tenants.Tenant

  @code_length 16
  @default_expiry_days 30

  schema "invitations" do
    field :code, :string
    field :used_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    belongs_to :tenant, Tenant
    belongs_to :invited_by, User
    belongs_to :used_by, User

    timestamps()
  end

  @doc "Changeset for creating an invitation."
  def create_changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:tenant_id, :invited_by_id])
    |> validate_required([:invited_by_id, :tenant_id])
    |> put_code()
    |> put_expires_at()
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:invited_by_id)
    |> unique_constraint(:code)
  end

  @doc "Changeset for marking an invitation as used."
  def use_changeset(invitation, %User{id: user_id}) do
    invitation
    |> change(used_by_id: user_id, used_at: DateTime.utc_now())
    |> foreign_key_constraint(:used_by_id)
  end

  @doc "Returns true if the invitation is available (unused and not expired)."
  def available?(%__MODULE__{used_at: used_at, expires_at: expires_at}) do
    is_nil(used_at) and DateTime.compare(DateTime.utc_now(), expires_at) == :lt
  end

  @doc "Returns the status of the invitation."
  def status(%__MODULE__{} = invitation) do
    cond do
      invitation.used_at != nil -> :used
      DateTime.compare(DateTime.utc_now(), invitation.expires_at) != :lt -> :expired
      true -> :available
    end
  end

  defp put_code(changeset) do
    put_change(changeset, :code, generate_code())
  end

  defp put_expires_at(changeset) do
    expires_at = DateTime.utc_now() |> DateTime.add(@default_expiry_days, :day)
    put_change(changeset, :expires_at, expires_at)
  end

  defp generate_code do
    :crypto.strong_rand_bytes(@code_length) |> Base.url_encode64(padding: false)
  end
end
