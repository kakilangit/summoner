defmodule SummonerWeb.API.V1.AdminJSON do
  @moduledoc "JSON rendering for admin endpoints."

  import SummonerWeb.API.PaginationJSON

  alias Summoner.Domain.Schemas.Invitation

  def tenants(%{page: page}) do
    %{items: Enum.map(page.entries, &tenant_data/1), meta: page_meta(page)}
  end

  def users(%{page: page}) do
    %{items: Enum.map(page.entries, &user_data/1), meta: page_meta(page)}
  end

  def user(%{user: user}) do
    user_data(user)
  end

  def invitations(%{page: page}) do
    %{items: Enum.map(page.entries, &invitation_data/1), meta: page_meta(page)}
  end

  def stats(%{stats: stats}) do
    stats
  end

  defp tenant_data(tenant) do
    %{
      id: tenant.id,
      name: tenant.name,
      disabled_at: tenant.disabled_at,
      inserted_at: tenant.inserted_at,
      updated_at: tenant.updated_at
    }
  end

  defp user_data(user) do
    %{
      id: user.id,
      email: user.email,
      role: user.role,
      confirmed_at: user.confirmed_at,
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end

  defp invitation_data(invitation) do
    %{
      id: invitation.id,
      code: invitation.code,
      tenant_id: invitation.tenant_id,
      status: Invitation.status(invitation),
      expires_at: invitation.expires_at,
      inserted_at: invitation.inserted_at
    }
  end
end
