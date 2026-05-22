defmodule Summoner.Domain.Schemas.PluginContainer do
  @moduledoc """
  Schema for plugin containers.

  One row per unique running image digest (shared), or per
  tenant for isolated plugins.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Tenant

  @statuses ~w(starting running error stopped)a

  schema "plugin_containers" do
    field :image, :string
    field :digest, :string
    field :container_id, :string
    field :container_name, :string
    field :host, :string
    field :port, :integer, default: 9999
    field :status, Ecto.Enum, values: @statuses, default: :starting
    field :callback_token, :string

    belongs_to :tenant, Tenant

    timestamps()
  end

  def changeset(container, attrs) do
    container
    |> cast(attrs, [
      :image,
      :digest,
      :container_id,
      :container_name,
      :host,
      :port,
      :status,
      :callback_token,
      :tenant_id
    ])
    |> validate_required([:image, :digest, :container_name, :host, :port, :callback_token])
    |> validate_number(:port, greater_than: 0, less_than: 65_536)
  end

  def status_changeset(container, status) do
    container
    |> change(%{status: status})
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Build a container name from an image reference.

  Strips the tag so that upgrading an image replaces the existing container
  instead of leaving the old one running alongside the new one.
  """
  def container_name_from_image(image) do
    image
    |> String.split("/")
    |> List.last()
    |> String.split(":")
    |> List.first()
    |> String.replace(".", "-")
    |> then(&"summoner-plugin-#{&1}")
  end
end
