defmodule Summoner.Ports.Persistence.Invitations.Adapter do
  @moduledoc "Behaviour for invitations persistence operations."

  # Invitations
  @callback create_tenant_invitation(struct(), String.t()) ::
              {:ok, struct()} | {:error, term()}
  @callback use_invitation(String.t(), struct()) ::
              {:ok, struct()} | {:error, :invalid_code | :invitation_unavailable}
  @callback get_invitation_by_code(String.t()) :: struct() | nil
  @callback get_invitation!(String.t()) :: struct()
  @callback list_all_invitations() :: struct()
  @callback list_all_invitations(keyword()) :: struct()
  @callback list_tenant_invitations(String.t()) :: struct()
  @callback list_tenant_invitations(String.t(), keyword()) :: struct()
  @callback list_user_tenant_invitations(struct(), String.t()) :: struct()
  @callback list_user_tenant_invitations(struct(), String.t(), keyword()) :: struct()

  # Quotas
  @callback remaining_quota(struct(), String.t()) :: :unlimited | integer()
  @callback add_quota(struct(), String.t(), integer()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback get_quota(String.t(), String.t()) :: struct() | nil
  @callback list_all_quotas() :: struct()
  @callback list_all_quotas(keyword()) :: struct()
  @callback list_tenant_quotas(String.t()) :: struct()
  @callback list_tenant_quotas(String.t(), keyword()) :: struct()
end
