defmodule Summoner.Domain.Schemas.Provider do
  @moduledoc """
  Schema for inference providers.

  A provider represents a configured LLM endpoint (Ollama,
  OpenAI, Anthropic, etc.) within a workspace or tenant.

  A provider belongs to exactly one of a workspace or a tenant (XOR).
  Tenant-scoped providers are shared across all workspaces in the tenant.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Secret
  alias Summoner.Domain.Schemas.Tenant
  alias Summoner.Domain.Schemas.Workspace
  alias Summoner.Domain.Types.Presets

  @api_formats ~w(openai anthropic custom)a
  @types ~w(local cloud)a
  @statuses ~w(online offline unknown)a

  schema "providers" do
    field :name, :string
    field :kind, :string
    field :api_format, Ecto.Enum, values: @api_formats
    field :type, Ecto.Enum, values: @types
    field :base_url, :string
    field :status, Ecto.Enum, values: @statuses, default: :unknown
    field :cached_models, {:array, :string}, default: []

    belongs_to :workspace, Workspace
    belongs_to :tenant, Tenant
    belongs_to :api_key_secret, Secret

    timestamps()
  end

  @doc "All supported provider kinds, derived from presets."
  def kinds do
    Presets.providers()
    |> Map.keys()
    |> Enum.sort()
  end

  @doc "All supported API formats."
  def api_formats, do: @api_formats

  @doc "All supported provider types."
  def types, do: @types

  @doc """
  Returns the decrypted API key from the associated secret, or nil.

  Requires the `:api_key_secret` association to be preloaded.
  """
  def api_key(%__MODULE__{api_key_secret: %Secret{encrypted_value: value}}), do: value
  def api_key(%__MODULE__{}), do: nil

  @doc """
  Changeset for creating or updating a provider.
  """
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [
      :name,
      :kind,
      :api_format,
      :type,
      :base_url,
      :api_key_secret_id,
      :status,
      :workspace_id,
      :tenant_id
    ])
    |> validate_required([:name, :kind, :api_format, :type, :base_url])
    |> validate_inclusion(:kind, kinds())
    |> validate_length(:name, min: 1, max: 100)
    |> validate_url(:base_url)
    |> validate_scope()
    |> unique_constraint([:workspace_id, :name])
    |> unique_constraint([:tenant_id, :name])
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:api_key_secret_id)
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

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
          []

        _ ->
          [{field, "must be a valid HTTP(S) URL"}]
      end
    end)
  end
end
