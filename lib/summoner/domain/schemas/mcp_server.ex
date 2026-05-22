defmodule Summoner.Domain.Schemas.McpServer do
  @moduledoc """
  Schema for MCP (Model Context Protocol) servers.

  An MCP server provides tools to Agents via either a stdio Port
  (local process) or Streamable HTTP transport (remote endpoint).

  A server belongs to exactly one of a workspace or a tenant (XOR).
  Tenant-scoped servers are shared across all workspaces in the tenant.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  schema "mcp_servers" do
    field :name, :string
    field :transport, Ecto.Enum, values: [:stdio, :http, :managed]
    field :command_or_url, :string
    field :config, :map, default: %{}

    belongs_to :workspace, Summoner.Domain.Schemas.Workspace
    belongs_to :tenant, Summoner.Domain.Schemas.Tenant

    has_many :agent_mcp_servers, Summoner.Domain.Schemas.AgentMcpServer
    has_many :agents, through: [:agent_mcp_servers, :agent]

    timestamps()
  end

  def changeset(mcp_server, attrs) do
    mcp_server
    |> cast(attrs, [:name, :transport, :command_or_url, :config, :workspace_id, :tenant_id])
    |> validate_required([:name, :transport, :command_or_url])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_transport_specific()
    |> validate_scope()
    |> unique_constraint([:workspace_id, :name])
    |> unique_constraint([:tenant_id, :name])
  end

  defp validate_transport_specific(changeset) do
    case get_field(changeset, :transport) do
      :http ->
        changeset
        |> validate_format(:command_or_url, ~r/^https?:\/\//, message: "must be a valid URL")

      :stdio ->
        changeset
        |> validate_length(:command_or_url, min: 1, message: "command is required")

      :managed ->
        # Managed by plugin system — command_or_url holds the OCI image reference
        changeset
        |> validate_length(:command_or_url, min: 1, message: "image reference is required")

      _ ->
        changeset
    end
  end

  defp validate_scope(changeset) do
    tenant_id = get_field(changeset, :tenant_id)
    workspace_id = get_field(changeset, :workspace_id)

    cond do
      is_nil(tenant_id) and is_nil(workspace_id) ->
        add_error(changeset, :base, "must belong to either a tenant or a workspace")

      not is_nil(tenant_id) and not is_nil(workspace_id) ->
        add_error(changeset, :base, "cannot belong to both a tenant and a workspace")

      true ->
        changeset
    end
  end
end
