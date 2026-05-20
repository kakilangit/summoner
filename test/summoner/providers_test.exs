defmodule Summoner.Adapters.Persistence.ProvidersTest do
  use Summoner.DataCase

  import Mox

  alias Summoner.Adapters.Persistence.Providers
  alias Summoner.Domain.Schemas.Provider
  alias Summoner.Ports.HTTPClientMock

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup :verify_on_exit!

  defp create_scope_and_workspace(_context) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    %{scope: scope, workspace: workspace}
  end

  describe "create_provider/2" do
    setup :create_scope_and_workspace

    test "creates a provider with valid attrs", %{scope: scope, workspace: workspace} do
      attrs = valid_provider_attributes(workspace.id)

      assert {:ok, %Provider{} = provider} = Providers.create_provider(scope, attrs)
      assert provider.name == attrs.name
      assert provider.kind == "ollama"
      assert provider.api_format == :openai
      assert provider.type == :local
      assert provider.base_url == "http://localhost:11434"
      assert provider.status == :unknown
    end

    test "requires mandatory fields", %{scope: scope} do
      assert {:error, changeset} = Providers.create_provider(scope, %{})
      errors = errors_on(changeset)
      assert errors[:name]
      assert errors[:kind]
      assert errors[:base_url]
      assert errors[:base]
    end

    test "validates base_url format", %{scope: scope, workspace: workspace} do
      attrs = valid_provider_attributes(workspace.id, %{base_url: "not-a-url"})
      assert {:error, changeset} = Providers.create_provider(scope, attrs)
      assert "must be a valid HTTP(S) URL" in errors_on(changeset).base_url
    end

    test "enforces unique name per workspace", %{scope: scope, workspace: workspace} do
      provider_fixture(scope, workspace.id, %{name: "dupe"})
      attrs = valid_provider_attributes(workspace.id, %{name: "dupe"})
      assert {:error, changeset} = Providers.create_provider(scope, attrs)
      assert "has already been taken" in errors_on(changeset).workspace_id
    end

    test "allows same name in different workspaces", %{scope: scope, workspace: workspace} do
      provider_fixture(scope, workspace.id, %{name: "shared-name"})

      other_scope = user_scope_fixture()
      other_workspace = workspace_fixture(other_scope)

      attrs = valid_provider_attributes(other_workspace.id, %{name: "shared-name"})
      assert {:ok, %Provider{}} = Providers.create_provider(other_scope, attrs)
    end
  end

  describe "list_providers/2" do
    setup :create_scope_and_workspace

    test "returns providers for a workspace", %{scope: scope, workspace: workspace} do
      provider = provider_fixture(scope, workspace.id)

      assert [%Provider{id: id}] =
               Providers.list_providers(scope, workspace.id, workspace.tenant_id)

      assert id == provider.id
    end

    test "does not return providers from other workspaces", %{scope: scope, workspace: workspace} do
      _provider = provider_fixture(scope, workspace.id)

      other_scope = user_scope_fixture()
      other_workspace = workspace_fixture(other_scope)

      assert [] =
               Providers.list_providers(
                 other_scope,
                 other_workspace.id,
                 other_workspace.tenant_id
               )
    end
  end

  describe "get_provider!/3" do
    setup :create_scope_and_workspace

    test "returns the provider", %{scope: scope, workspace: workspace} do
      provider = provider_fixture(scope, workspace.id)
      fetched = Providers.get_provider!(scope, workspace.id, workspace.tenant_id, provider.id)
      assert fetched.id == provider.id
    end

    test "raises when provider belongs to another workspace", %{
      scope: scope,
      workspace: workspace
    } do
      provider = provider_fixture(scope, workspace.id)

      other_scope = user_scope_fixture()
      other_workspace = workspace_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn ->
        Providers.get_provider!(
          other_scope,
          other_workspace.id,
          other_workspace.tenant_id,
          provider.id
        )
      end
    end
  end

  describe "update_provider/3" do
    setup :create_scope_and_workspace

    test "updates the provider", %{scope: scope, workspace: workspace} do
      provider = provider_fixture(scope, workspace.id)
      assert {:ok, updated} = Providers.update_provider(scope, provider, %{name: "new-name"})
      assert updated.name == "new-name"
    end

    test "validates changes", %{scope: scope, workspace: workspace} do
      provider = provider_fixture(scope, workspace.id)
      assert {:error, changeset} = Providers.update_provider(scope, provider, %{base_url: "bad"})
      assert "must be a valid HTTP(S) URL" in errors_on(changeset).base_url
    end
  end

  describe "delete_provider/2" do
    setup :create_scope_and_workspace

    test "deletes the provider", %{scope: scope, workspace: workspace} do
      provider = provider_fixture(scope, workspace.id)
      assert {:ok, %Provider{}} = Providers.delete_provider(scope, provider)

      assert_raise Ecto.NoResultsError, fn ->
        Providers.get_provider!(scope, workspace.id, workspace.tenant_id, provider.id)
      end
    end
  end

  # -------------------------------------------------------------------
  # Model listing
  # -------------------------------------------------------------------

  describe "available_models/2" do
    setup :create_scope_and_workspace

    test "returns live models and caches them", %{scope: scope, workspace: workspace} do
      provider = provider_fixture(scope, workspace.id)

      HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:ok, %{status: 200, body: %{"data" => [%{"id" => "gpt-4o"}, %{"id" => "gpt-4o-mini"}]}}}
      end)

      assert {:ok, ["gpt-4o", "gpt-4o-mini"]} = Providers.available_models(scope, provider)

      # Verify cache was updated
      updated = Repo.get!(Provider, provider.id)
      assert updated.cached_models == ["gpt-4o", "gpt-4o-mini"]
    end

    test "falls back to cached models on failure", %{scope: scope, workspace: workspace} do
      provider = provider_fixture(scope, workspace.id)

      provider =
        provider
        |> Ecto.Changeset.change(cached_models: ["cached-model"])
        |> Repo.update!()
        |> Repo.preload(:api_key_secret)

      HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:error, %Mint.TransportError{reason: :econnrefused}}
      end)

      assert {:ok, ["cached-model"]} = Providers.available_models(scope, provider)
    end

    test "returns empty list when no cache and provider offline", %{
      scope: scope,
      workspace: workspace
    } do
      provider = provider_fixture(scope, workspace.id)

      HTTPClientMock
      |> expect(:get, fn _url, _opts ->
        {:error, :timeout}
      end)

      assert {:ok, []} = Providers.available_models(scope, provider)
    end
  end
end
