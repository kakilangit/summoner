defmodule Summoner.WorkspacesFixtures do
  @moduledoc """
  Test helpers for creating workspace-related entities.
  """

  alias Summoner.Workspaces

  import Summoner.TenantsFixtures

  def unique_workspace_name, do: "workspace-#{System.unique_integer([:positive])}"

  def valid_workspace_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{name: unique_workspace_name()})
  end

  def workspace_fixture(scope, attrs \\ %{}) do
    tenant = tenant_fixture(scope)

    {:ok, workspace} =
      attrs
      |> valid_workspace_attributes()
      |> then(&Workspaces.create_workspace(scope, tenant.id, &1))

    workspace
  end
end
