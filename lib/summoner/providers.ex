defmodule Summoner.Providers do
  @moduledoc """
  The Providers context.

  Manages LLM provider configurations within workspaces and tenants.
  """

  import Ecto.Query, warn: false

  alias Summoner.Inference
  alias Summoner.Pagination
  alias Summoner.Providers.Provider
  alias Summoner.Repo
  alias Summoner.Workers.CopilotPoller

  alias Arcanum.ModelProfile.Resolver, as: ProfileResolver

  alias Arcanum.Auth.Copilot, as: CopilotAuth

  @doc """
  Creates a provider within a workspace or tenant.
  """
  def create_provider(%{user: _user}, attrs) do
    %Provider{}
    |> Provider.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists all providers for a workspace and its tenant.
  """
  def list_providers(%{user: _user}, workspace_id, tenant_id) do
    Provider
    |> where_scope(workspace_id, tenant_id)
    |> order_by([p], asc: p.name)
    |> Repo.all()
    |> Repo.preload(:api_key_secret)
  end

  @doc """
  Lists providers for a workspace and its tenant with pagination.
  """
  def list_providers_paginated(%{user: _user}, workspace_id, tenant_id, opts \\ []) do
    page =
      Provider
      |> where_scope(workspace_id, tenant_id)
      |> Pagination.paginate(opts)

    %{page | entries: Repo.preload(page.entries, :api_key_secret)}
  end

  @doc """
  Gets a single provider scoped to a workspace or its tenant.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_provider!(%{user: _user}, workspace_id, tenant_id, provider_id) do
    Provider
    |> where_scope(workspace_id, tenant_id)
    |> Repo.get!(provider_id)
    |> Repo.preload(:api_key_secret)
  end

  @doc """
  Updates a provider.
  """
  def update_provider(%{user: _user}, %Provider{} = provider, attrs) do
    provider
    |> Provider.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a provider.
  """
  def delete_provider(%{user: _user}, %Provider{} = provider) do
    provider
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.foreign_key_constraint(:agents,
      name: :agents_provider_id_fkey,
      message: "vessel is still used by one or more familiars"
    )
    |> Repo.delete()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking provider changes.
  """
  def change_provider(%Provider{} = provider, attrs \\ %{}) do
    Provider.changeset(provider, attrs)
  end

  # -------------------------------------------------------------------
  # Internal API (for cross-context and infrastructure use)
  # -------------------------------------------------------------------

  @doc """
  Lists all providers across all workspaces.

  Intended for infrastructure use (e.g. Discovery probing).
  """
  def list_all_providers do
    Provider
    |> order_by([p], asc: p.name)
    |> Repo.all()
    |> Repo.preload(:api_key_secret)
  end

  @doc """
  Updates a provider's status.

  Intended for infrastructure use (e.g. Discovery probing).
  """
  def update_status(%Provider{} = provider, status)
      when status in [:online, :offline, :unknown] do
    provider
    |> Ecto.Changeset.change(status: status)
    |> Repo.update()
  end

  @doc """
  Updates the cached models list for a provider.
  """
  def update_cached_models(%Provider{} = provider, models) when is_list(models) do
    provider
    |> Ecto.Changeset.change(cached_models: models)
    |> Repo.update()
  end

  @doc """
  Returns available models for a provider.

  Attempts a live fetch via the inference adapter. On success, caches
  the result in the provider row. On failure, returns the cached models.
  """
  def available_models(%{user: _user}, %Provider{} = provider) do
    case Inference.Gateway.list_models(provider) do
      {:ok, models} ->
        update_cached_models(provider, models)
        {:ok, models}

      {:error, _reason} ->
        {:ok, provider.cached_models || []}
    end
  end

  @doc """
  Filters a list of model names by capability using Arcanum profiles.

  Supported capabilities:
  - `:chat` — models that support system role and tools (excludes image/video-only)
  - `:image` — models with `supports_image_generation: true`
  - `:video` — models with `supports_video_generation: true`
  """
  @spec filter_models_by_capability([String.t()], String.t(), atom()) :: [String.t()]
  def filter_models_by_capability(models, provider_kind, capability) do
    Enum.filter(models, fn model ->
      profile = ProfileResolver.resolve(provider_kind, model)
      model_has_capability?(profile, capability)
    end)
  end

  defp model_has_capability?(profile, :chat) do
    not profile.supports_image_generation and not profile.supports_video_generation
  end

  defp model_has_capability?(profile, :image), do: profile.supports_image_generation
  defp model_has_capability?(profile, :video), do: profile.supports_video_generation

  # -------------------------------------------------------------------
  # Copilot device code connect
  # -------------------------------------------------------------------

  @doc """
  Starts the Copilot OAuth device code flow for a provider.

  Returns `{:ok, device_flow}` with `user_code` and `verification_uri`
  for display, and enqueues a `CopilotPoller` Oban job to poll for
  the token in the background.
  """
  def start_copilot_connect(%Provider{kind: "github-copilot"} = provider) do
    case CopilotAuth.start_device_flow() do
      {:ok, device_flow} ->
        %{
          "provider_id" => provider.id,
          "workspace_id" => provider.workspace_id,
          "device_code" => device_flow.device_code,
          "interval" => device_flow.interval,
          "attempt" => 1
        }
        |> CopilotPoller.new()
        |> Oban.insert()

        {:ok, device_flow}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def start_copilot_connect(%Provider{kind: kind}) do
    {:error, {:not_copilot, kind}}
  end

  # -------------------------------------------------------------------
  # Tenant-scoped operations
  # -------------------------------------------------------------------

  @doc """
  Lists providers scoped to a tenant only.
  """
  def list_tenant_providers(tenant_id) do
    Provider
    |> where([p], p.tenant_id == ^tenant_id)
    |> order_by([p], asc: p.name)
    |> Repo.all()
    |> Repo.preload(:api_key_secret)
  end

  @doc """
  Lists tenant-scoped providers with pagination.
  """
  def list_tenant_providers_paginated(tenant_id, opts \\ []) do
    page =
      Provider
      |> where([p], p.tenant_id == ^tenant_id)
      |> Pagination.paginate(opts)

    %{page | entries: Repo.preload(page.entries, :api_key_secret)}
  end

  @doc """
  Gets a tenant-scoped provider by ID.
  """
  def get_tenant_provider!(tenant_id, id) do
    Provider
    |> where([p], p.tenant_id == ^tenant_id)
    |> Repo.get!(id)
    |> Repo.preload(:api_key_secret)
  end

  defp where_scope(query, workspace_id, tenant_id) do
    where(query, [p], p.workspace_id == ^workspace_id or p.tenant_id == ^tenant_id)
  end
end
