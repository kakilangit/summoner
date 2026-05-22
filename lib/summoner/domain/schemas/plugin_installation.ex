defmodule Summoner.Domain.Schemas.PluginInstallation do
  @moduledoc """
  Schema for plugin installations (Grimoires).

  A plugin is an OCI image that speaks MCP, extended with Summoner-specific
  methods for capabilities that MCP doesn't cover (webhooks, hooks, events,
  providers).

  Plugins are workspace-scoped. A plugin with `tools` capability is linked
  to an MCP server record. A plugin with `provider` capability is linked
  to a provider record.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.{McpServer, Provider, Workspace}

  @capabilities ~w(tools webhooks hooks events provider theme)
  @statuses ~w(installed enabled disabled error)a

  schema "plugin_installations" do
    field :name, :string
    field :ref, :string
    field :version, :string
    field :capabilities, {:array, :string}, default: []
    field :manifest, :map
    field :config, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :installed
    field :error_message, :string

    belongs_to :mcp_server, McpServer
    belongs_to :provider, Provider
    belongs_to :workspace, Workspace

    has_many :plugin_conversations, Summoner.Domain.Schemas.PluginConversation,
      foreign_key: :plugin_id

    timestamps()
  end

  def changeset(plugin, attrs) do
    plugin
    |> cast(attrs, [
      :name,
      :ref,
      :version,
      :capabilities,
      :manifest,
      :config,
      :status,
      :error_message,
      :mcp_server_id,
      :provider_id,
      :workspace_id
    ])
    |> validate_required([:name, :ref, :version, :capabilities, :manifest, :workspace_id])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:ref, is: 12)
    |> validate_capabilities()
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:mcp_server_id)
    |> foreign_key_constraint(:provider_id)
    |> unique_constraint([:workspace_id, :name])
    |> unique_constraint([:workspace_id, :ref])
  end

  def status_changeset(plugin, status, error_message \\ nil) do
    plugin
    |> change(%{status: status, error_message: error_message})
    |> validate_inclusion(:status, @statuses)
  end

  defp validate_capabilities(changeset) do
    case get_field(changeset, :capabilities) do
      nil ->
        changeset

      caps ->
        if Enum.all?(caps, &(&1 in @capabilities)) do
          changeset
        else
          invalid = Enum.reject(caps, &(&1 in @capabilities))
          add_error(changeset, :capabilities, "invalid capabilities: #{Enum.join(invalid, ", ")}")
        end
    end
  end

  def valid_capabilities, do: @capabilities

  @doc """
  Compute a stable 12-char ref from an OCI image path (without version tag).

  Examples:
    "docker.io/kakilangit/grimoire-slack:0.1.3" -> "a1b2c3d4e5f6"
    "docker.io/kakilangit/grimoire-slack"        -> "a1b2c3d4e5f6"
  """
  def compute_ref(image) do
    image
    |> String.replace(~r/:[^\/]+$/, "")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end
end
