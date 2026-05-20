defmodule Summoner.Domain.Schemas.MediaProvider do
  @moduledoc """
  Schema for workspace-scoped or tenant-scoped media providers.

  A Forge references an existing Gateway (Provider) for API access
  and declares default image/video models (souls) for media generation.
  This allows an agent using one gateway for chat to generate media
  via a different gateway.

  A media provider belongs to exactly one of a workspace or a tenant (XOR).
  Tenant-scoped media providers are shared across all workspaces in the tenant.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Provider
  alias Summoner.Domain.Schemas.Tenant
  alias Summoner.Domain.Schemas.Workspace

  schema "media_providers" do
    field :name, :string
    field :default_image_model, :string
    field :default_video_model, :string
    field :max_concurrent_jobs, :integer, default: 3
    field :config, :map, default: %{}

    belongs_to :workspace, Workspace
    belongs_to :tenant, Tenant
    belongs_to :provider, Provider

    timestamps()
  end

  @required_fields ~w(name provider_id)a
  @optional_fields ~w(workspace_id tenant_id default_image_model default_video_model max_concurrent_jobs config)a

  def changeset(media_provider, attrs) do
    media_provider
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_number(:max_concurrent_jobs, greater_than: 0, less_than_or_equal_to: 10)
    |> validate_scope()
    |> unique_constraint([:workspace_id, :name],
      message: "a media provider with this name already exists"
    )
    |> unique_constraint([:tenant_id, :name],
      message: "a media provider with this name already exists"
    )
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:provider_id)
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
