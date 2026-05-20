defmodule Summoner.Adapters.Persistence.Invitations do
  @moduledoc """
  Context for managing invitations and invitation quotas.

  All invitations are tenant-scoped. Registration is always tied to a tenant.
  """

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Pagination
  alias Summoner.Domain.Schemas.{Invitation, InvitationQuota}
  alias Summoner.Domain.Schemas.TenantMembership
  alias Summoner.Domain.Schemas.User
  alias Summoner.Repo

  # -------------------------------------------------------------------
  # Invitations
  # -------------------------------------------------------------------

  @doc """
  Creates a tenant-scoped invitation.

  Tenant admins have unlimited tenant quota. Other users must have
  a tenant quota record with amount > 0.
  """
  def create_tenant_invitation(%User{} = user, tenant_id) when is_binary(tenant_id) do
    Repo.transact(fn ->
      with :ok <- check_quota(user, tenant_id),
           {:ok, invitation} <- insert_invitation(user, tenant_id) do
        decrement_quota(user, tenant_id)
        {:ok, invitation}
      end
    end)
  end

  defp insert_invitation(%User{id: user_id}, tenant_id) do
    %Invitation{}
    |> Invitation.create_changeset(%{invited_by_id: user_id, tenant_id: tenant_id})
    |> Repo.insert()
  end

  @doc """
  Validates and uses an invitation code.

  Returns `{:ok, invitation}` if the code is valid, unused, and not expired.
  Marks the invitation as used by the given user.
  """
  def use_invitation(code, %User{} = user) do
    case get_invitation_by_code(code) do
      nil ->
        {:error, :invalid_code}

      %Invitation{} = invitation ->
        if Invitation.available?(invitation) do
          invitation
          |> Invitation.use_changeset(user)
          |> Repo.update()
        else
          {:error, :invitation_unavailable}
        end
    end
  end

  @doc "Gets an invitation by code."
  def get_invitation_by_code(code) when is_binary(code) do
    Repo.get_by(Invitation, code: code)
  end

  @doc "Gets an invitation by ID, preloading associations."
  def get_invitation!(id) do
    Invitation
    |> Repo.get!(id)
    |> Repo.preload([:invited_by, :used_by, :tenant])
  end

  @doc "Lists all invitations across all tenants (admin view) with pagination."
  def list_all_invitations(opts \\ []) do
    Invitation
    |> order_by([i], desc: i.inserted_at)
    |> preload([:invited_by, :used_by, :tenant])
    |> Pagination.paginate(opts)
  end

  @doc "Lists tenant-scoped invitations with pagination."
  def list_tenant_invitations(tenant_id, opts \\ []) do
    Invitation
    |> where([i], i.tenant_id == ^tenant_id)
    |> order_by([i], desc: i.inserted_at)
    |> preload([:invited_by, :used_by])
    |> Pagination.paginate(opts)
  end

  @doc "Lists invitations created by a user for a specific tenant."
  def list_user_tenant_invitations(%User{id: user_id}, tenant_id, opts \\ []) do
    Invitation
    |> where([i], i.invited_by_id == ^user_id and i.tenant_id == ^tenant_id)
    |> order_by([i], desc: i.inserted_at)
    |> preload([:used_by])
    |> Pagination.paginate(opts)
  end

  # -------------------------------------------------------------------
  # Quotas
  # -------------------------------------------------------------------

  @doc """
  Returns the remaining quota for a user in a tenant.

  Returns `:unlimited` for tenant admins. Otherwise returns the integer amount.
  """
  def remaining_quota(%User{} = user, tenant_id) when is_binary(tenant_id) do
    if unlimited_quota?(user, tenant_id) do
      :unlimited
    else
      case get_quota(user.id, tenant_id) do
        %InvitationQuota{amount: amount} -> amount
        nil -> 0
      end
    end
  end

  @doc """
  Adds quota to a user for a specific tenant. Creates the quota record if it doesn't exist.

  Returns `{:ok, quota}` or `{:error, changeset}`.
  """
  def add_quota(%User{id: user_id}, tenant_id, amount)
      when is_binary(tenant_id) and is_integer(amount) and amount > 0 do
    case get_quota(user_id, tenant_id) do
      %InvitationQuota{} = quota ->
        quota
        |> InvitationQuota.add_changeset(amount)
        |> Repo.update()

      nil ->
        %InvitationQuota{}
        |> InvitationQuota.changeset(%{user_id: user_id, tenant_id: tenant_id, amount: amount})
        |> Repo.insert()
    end
  end

  @doc "Gets the quota record for a user in a tenant."
  def get_quota(user_id, tenant_id) when is_binary(tenant_id) do
    Repo.one(
      from(q in InvitationQuota,
        where: q.user_id == ^user_id and q.tenant_id == ^tenant_id,
        limit: 1
      )
    )
  end

  @doc "Lists all quota records across all tenants (admin view) with pagination."
  def list_all_quotas(opts \\ []) do
    InvitationQuota
    |> preload([:user, :tenant])
    |> order_by([q], desc: q.amount)
    |> Pagination.paginate(opts)
  end

  @doc "Lists tenant-scoped quota records with pagination."
  def list_tenant_quotas(tenant_id, opts \\ []) do
    InvitationQuota
    |> where([q], q.tenant_id == ^tenant_id)
    |> preload(:user)
    |> order_by([q], desc: q.amount)
    |> Pagination.paginate(opts)
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp check_quota(%User{} = user, tenant_id) do
    if unlimited_quota?(user, tenant_id) do
      :ok
    else
      case get_quota(user.id, tenant_id) do
        %InvitationQuota{amount: amount} when amount > 0 -> :ok
        _ -> {:error, :no_quota}
      end
    end
  end

  defp decrement_quota(%User{} = user, tenant_id) do
    if unlimited_quota?(user, tenant_id), do: :ok, else: do_decrement(user.id, tenant_id)
  end

  defp do_decrement(user_id, tenant_id) do
    case get_quota(user_id, tenant_id) do
      %InvitationQuota{} = quota -> apply_decrement(quota)
      nil -> :ok
    end
  end

  defp apply_decrement(quota) do
    case InvitationQuota.decrement_changeset(quota) do
      %Ecto.Changeset{} = changeset -> Repo.update!(changeset)
      {:error, :no_quota} -> :ok
    end
  end

  defp unlimited_quota?(%User{id: user_id}, tenant_id) do
    Repo.exists?(
      from(m in TenantMembership,
        where: m.user_id == ^user_id and m.tenant_id == ^tenant_id and m.role == :admin
      )
    )
  end
end
