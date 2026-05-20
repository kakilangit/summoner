defmodule Summoner.Adapters.Persistence.Secrets do
  @moduledoc """
  The Secrets context (Seals).

  Manages workspace-scoped and tenant-scoped encrypted secrets. Secrets
  are referenced by name (`$SECRET_NAME`) in MCP server configs and
  resolved at runtime before passing to adapters.

  Workspace-local secrets override tenant-shared secrets of the same name.
  """

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Pagination
  alias Summoner.Domain.Schemas.Secret
  alias Summoner.Repo

  @doc """
  Creates a secret in a workspace or tenant.
  """
  def create_secret(%{user: _user}, attrs) do
    %Secret{}
    |> Secret.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists secrets for a workspace and its tenant.
  """
  def list_secrets(%{user: _user}, workspace_id, tenant_id) do
    Secret
    |> where_scope(workspace_id, tenant_id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Lists secrets for a workspace and its tenant with pagination.
  """
  def list_secrets_paginated(%{user: _user}, workspace_id, tenant_id, opts \\ []) do
    Secret
    |> where_scope(workspace_id, tenant_id)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a secret by ID, scoped to workspace or tenant.
  """
  def get_secret!(%{user: _user}, workspace_id, tenant_id, secret_id) do
    Secret
    |> where_scope(workspace_id, tenant_id)
    |> Repo.get!(secret_id)
  end

  @doc """
  Updates a secret.
  """
  def update_secret(%{user: _user}, %Secret{} = secret, attrs) do
    secret
    |> Secret.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a secret.

  Returns `{:error, :in_use}` if MCP servers reference `$SECRET_NAME`
  in their config.
  """
  def delete_secret(%{user: _user}, %Secret{} = secret) do
    ref = "$#{secret.name}"

    scope_query =
      if secret.workspace_id do
        where(Summoner.Domain.Schemas.McpServer, [s], s.workspace_id == ^secret.workspace_id)
      else
        where(Summoner.Domain.Schemas.McpServer, [s], s.tenant_id == ^secret.tenant_id)
      end

    in_use =
      scope_query
      |> Repo.all()
      |> Enum.any?(fn server ->
        server.config
        |> Map.get("env", %{})
        |> Map.values()
        |> Enum.any?(&String.contains?(&1, ref))
      end)

    if in_use do
      {:error, :in_use, "seal is still referenced by one or more runes"}
    else
      Repo.delete(secret)
    end
  end

  @doc """
  Resolves `$SECRET_NAME` references in a map of string key-value pairs.

  Values starting with `$` are looked up in the workspace's secrets first,
  then tenant secrets. Workspace secrets take precedence over tenant secrets.

  Returns `{:ok, resolved_map}` or `{:error, missing_names}`.
  """
  def resolve(workspace_id, tenant_id, env_map) when is_map(env_map) do
    refs =
      env_map
      |> Map.values()
      |> Enum.flat_map(&extract_refs/1)
      |> Enum.uniq()

    if refs == [] do
      {:ok, env_map}
    else
      do_resolve(workspace_id, tenant_id, env_map, refs)
    end
  end

  def resolve(_workspace_id, _tenant_id, nil), do: {:ok, %{}}

  defp do_resolve(workspace_id, tenant_id, env_map, refs) do
    secret_map =
      workspace_id
      |> load_secrets_by_names(tenant_id, refs)
      |> Map.new(fn s -> {s.name, s.encrypted_value} end)

    missing = Enum.reject(refs, &Map.has_key?(secret_map, &1))

    if missing != [] do
      {:error, {:missing_secrets, missing}}
    else
      {:ok, resolve_map(env_map, secret_map)}
    end
  end

  defp resolve_map(env_map, secret_map) do
    Map.new(env_map, fn {k, v} ->
      {k, interpolate(v, secret_map)}
    end)
  end

  defp interpolate(value, secret_map) when is_binary(value) do
    Regex.replace(~r/\$([A-Z_][A-Z0-9_]*)/, value, fn _match, name ->
      Map.get(secret_map, name, "$#{name}")
    end)
  end

  @doc """
  Resolves a single value that may be a `$SECRET_NAME` reference.
  """
  def resolve_value(workspace_id, tenant_id, value) when is_binary(value) do
    refs = extract_refs(value)

    if refs == [] do
      {:ok, value}
    else
      secrets = load_secrets_by_names(workspace_id, tenant_id, refs)
      secret_map = Map.new(secrets, fn s -> {s.name, s.encrypted_value} end)
      missing = Enum.reject(refs, &Map.has_key?(secret_map, &1))

      if missing != [] do
        {:error, {:missing_secret, List.first(missing)}}
      else
        {:ok, interpolate(value, secret_map)}
      end
    end
  end

  def resolve_value(_workspace_id, _tenant_id, nil), do: {:ok, nil}

  # Extract all $WARD_NAME references from a value (supports inline interpolation)
  defp extract_refs(value) when is_binary(value) do
    Regex.scan(~r/\$([A-Z_][A-Z0-9_]*)/, value)
    |> Enum.map(fn [_full, name] -> name end)
  end

  defp extract_refs(_), do: []

  defp load_secrets_by_names(workspace_id, tenant_id, names) do
    # Load workspace secrets first (they take precedence)
    workspace_secrets =
      Secret
      |> where([s], s.workspace_id == ^workspace_id and s.name in ^names)
      |> Repo.all()

    found_names = Enum.map(workspace_secrets, & &1.name)
    remaining = Enum.reject(names, &(&1 in found_names))

    tenant_secrets =
      if remaining != [] and tenant_id do
        Secret
        |> where([s], s.tenant_id == ^tenant_id and s.name in ^remaining)
        |> Repo.all()
      else
        []
      end

    workspace_secrets ++ tenant_secrets
  end

  # -------------------------------------------------------------------
  # Tenant-scoped operations
  # -------------------------------------------------------------------

  @doc """
  Lists secrets scoped to a tenant only (not workspace).
  """
  def list_tenant_secrets(tenant_id) do
    Secret
    |> where([s], s.tenant_id == ^tenant_id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Lists tenant-scoped secrets with pagination.
  """
  def list_tenant_secrets_paginated(tenant_id, opts \\ []) do
    Secret
    |> where([s], s.tenant_id == ^tenant_id)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a tenant-scoped secret by ID.
  """
  def get_tenant_secret!(tenant_id, id) do
    Secret
    |> where([s], s.tenant_id == ^tenant_id)
    |> Repo.get!(id)
  end

  defp where_scope(query, workspace_id, tenant_id) do
    where(query, [s], s.workspace_id == ^workspace_id or s.tenant_id == ^tenant_id)
  end
end
