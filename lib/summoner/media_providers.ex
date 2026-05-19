defmodule Summoner.MediaProviders do
  @moduledoc """
  Media provider management context.

  Manages workspace-scoped and tenant-scoped media providers that
  handle image and video generation. Each media provider references
  an existing Gateway (Provider) for API access.
  """

  import Ecto.Query, warn: false

  alias Summoner.MediaProviders.MediaProvider
  alias Summoner.Repo

  @max_media_providers_per_workspace 10

  @doc """
  Lists media providers for a workspace and its tenant.
  """
  def list_media_providers(%{user: _user}, workspace_id, tenant_id) do
    MediaProvider
    |> where_scope(workspace_id, tenant_id)
    |> order_by([p], asc: p.name)
    |> limit(@max_media_providers_per_workspace)
    |> Repo.all()
    |> Repo.preload(provider: :api_key_secret)
  end

  @doc """
  Gets a single media provider by ID, scoped to a workspace or tenant.
  Raises `Ecto.NoResultsError` if not found.
  """
  def get_media_provider!(%{user: _user}, workspace_id, tenant_id, id) do
    MediaProvider
    |> where_scope(workspace_id, tenant_id)
    |> Repo.get!(id)
    |> Repo.preload(provider: :api_key_secret)
  end

  @doc """
  Gets a media provider by ID without scope (for Oban workers).
  """
  def get_media_provider!(id) do
    Repo.get!(MediaProvider, id)
    |> Repo.preload(provider: :api_key_secret)
  end

  @doc """
  Creates a media provider for a workspace or tenant.
  """
  def create_media_provider(%{user: _user}, attrs) do
    %MediaProvider{}
    |> MediaProvider.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a media provider.
  """
  def update_media_provider(%{user: _user}, %MediaProvider{} = provider, attrs) do
    provider
    |> MediaProvider.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a media provider.
  """
  def delete_media_provider(%{user: _user}, %MediaProvider{} = provider) do
    Repo.delete(provider)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking media provider changes.
  """
  def change_media_provider(%MediaProvider{} = provider, attrs \\ %{}) do
    MediaProvider.changeset(provider, attrs)
  end

  @doc """
  Returns the default media provider for a workspace by type (:image or :video).
  Uses the first provider that has the relevant default model set.
  Returns nil if none found.
  """
  def get_default_media_provider(workspace_id, type \\ :image) do
    field =
      case type do
        :image -> :default_image_model
        :video -> :default_video_model
      end

    MediaProvider
    |> where([p], p.workspace_id == ^workspace_id)
    |> where([p], not is_nil(field(p, ^field)))
    |> order_by([p], asc: p.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> maybe_preload()
  end

  @doc """
  Resolves the media provider for an agent. Falls back to workspace default.
  Returns nil if no media provider is available or the agent has no local config.
  """
  def resolve_media_provider(agent, type \\ :image)

  def resolve_media_provider(%{local_agent: nil}, _type), do: nil

  def resolve_media_provider(agent, type) do
    case agent.local_agent.media_provider_id do
      nil ->
        get_default_media_provider(agent.workspace_id, type)

      id ->
        case Repo.get(MediaProvider, id) do
          nil -> get_default_media_provider(agent.workspace_id, type)
          provider -> Repo.preload(provider, provider: :api_key_secret)
        end
    end
  end

  defp maybe_preload(nil), do: nil
  defp maybe_preload(provider), do: Repo.preload(provider, provider: :api_key_secret)

  # -------------------------------------------------------------------
  # Tenant-scoped operations
  # -------------------------------------------------------------------

  @doc """
  Lists media providers scoped to a tenant only.
  """
  def list_tenant_media_providers(tenant_id) do
    MediaProvider
    |> where([p], p.tenant_id == ^tenant_id)
    |> order_by([p], asc: p.name)
    |> limit(@max_media_providers_per_workspace)
    |> Repo.all()
    |> Repo.preload(provider: :api_key_secret)
  end

  @doc """
  Gets a tenant-scoped media provider by ID.
  """
  def get_tenant_media_provider!(tenant_id, id) do
    MediaProvider
    |> where([p], p.tenant_id == ^tenant_id)
    |> Repo.get!(id)
    |> Repo.preload(provider: :api_key_secret)
  end

  defp where_scope(query, workspace_id, tenant_id) do
    where(query, [p], p.workspace_id == ^workspace_id or p.tenant_id == ^tenant_id)
  end
end
