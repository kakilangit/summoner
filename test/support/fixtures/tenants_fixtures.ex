defmodule Summoner.TenantsFixtures do
  @moduledoc """
  Test helpers for creating tenant-related entities.
  """

  alias Summoner.Tenants

  def unique_tenant_name, do: "tenant-#{System.unique_integer([:positive])}"

  def valid_tenant_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_tenant_name()
    })
  end

  def tenant_fixture(scope, attrs \\ %{}) do
    {:ok, tenant} =
      attrs
      |> valid_tenant_attributes()
      |> then(&Tenants.create_tenant(scope, &1))

    tenant
  end
end
