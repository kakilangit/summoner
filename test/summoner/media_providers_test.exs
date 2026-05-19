defmodule Summoner.Adapters.Persistence.MediaProvidersTest do
  use Summoner.DataCase

  alias Summoner.Adapters.Persistence.MediaProviders

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.MediaProvidersFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup do
    user = user_fixture()
    scope = %Summoner.Domain.Schemas.Scope{user: user}
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)

    %{workspace: workspace, scope: scope, agent: agent, provider: provider}
  end

  describe "create_media_provider/2" do
    test "creates a media provider with valid attrs", ctx do
      {:ok, mp} =
        MediaProviders.create_media_provider(ctx.scope, %{
          workspace_id: ctx.workspace.id,
          provider_id: ctx.provider.id,
          name: "OpenAI Images",
          default_image_model: "gpt-image-1"
        })

      assert mp.name == "OpenAI Images"
      assert mp.provider_id == ctx.provider.id
      assert mp.default_image_model == "gpt-image-1"
    end

    test "rejects missing provider_id", ctx do
      {:error, changeset} =
        MediaProviders.create_media_provider(ctx.scope, %{
          workspace_id: ctx.workspace.id,
          name: "Bad"
        })

      assert errors_on(changeset).provider_id
    end

    test "enforces unique name per workspace", ctx do
      _mp1 =
        media_provider_fixture(ctx.scope, ctx.workspace.id, %{
          provider_id: ctx.provider.id,
          name: "Unique"
        })

      {:error, changeset} =
        MediaProviders.create_media_provider(ctx.scope, %{
          workspace_id: ctx.workspace.id,
          provider_id: ctx.provider.id,
          name: "Unique"
        })

      assert errors_on(changeset).workspace_id
    end
  end

  describe "list_media_providers/2" do
    test "lists providers for a workspace", ctx do
      mp = media_provider_fixture(ctx.scope, ctx.workspace.id, %{provider_id: ctx.provider.id})

      providers =
        MediaProviders.list_media_providers(ctx.scope, ctx.workspace.id, ctx.workspace.tenant_id)

      assert Enum.any?(providers, &(&1.id == mp.id))
    end
  end

  describe "get_media_provider!/3" do
    test "gets a provider by ID", ctx do
      mp = media_provider_fixture(ctx.scope, ctx.workspace.id, %{provider_id: ctx.provider.id})

      found =
        MediaProviders.get_media_provider!(
          ctx.scope,
          ctx.workspace.id,
          ctx.workspace.tenant_id,
          mp.id
        )

      assert found.id == mp.id
    end
  end

  describe "update_media_provider/3" do
    test "updates a provider", ctx do
      mp = media_provider_fixture(ctx.scope, ctx.workspace.id, %{provider_id: ctx.provider.id})

      {:ok, updated} =
        MediaProviders.update_media_provider(ctx.scope, mp, %{name: "Updated Name"})

      assert updated.name == "Updated Name"
    end
  end

  describe "delete_media_provider/2" do
    test "deletes a provider", ctx do
      mp = media_provider_fixture(ctx.scope, ctx.workspace.id, %{provider_id: ctx.provider.id})
      {:ok, _} = MediaProviders.delete_media_provider(ctx.scope, mp)

      assert_raise Ecto.NoResultsError, fn ->
        MediaProviders.get_media_provider!(
          ctx.scope,
          ctx.workspace.id,
          ctx.workspace.tenant_id,
          mp.id
        )
      end
    end
  end

  describe "resolve_media_provider/2" do
    test "returns nil when no media provider exists", ctx do
      assert MediaProviders.resolve_media_provider(ctx.agent) == nil
    end

    test "returns workspace default when agent has no media_provider_id", ctx do
      mp =
        media_provider_fixture(ctx.scope, ctx.workspace.id, %{
          provider_id: ctx.provider.id,
          default_image_model: "gpt-image-1"
        })

      result = MediaProviders.resolve_media_provider(ctx.agent)
      assert result.id == mp.id
    end

    test "returns agent's assigned media provider when set", ctx do
      mp = media_provider_fixture(ctx.scope, ctx.workspace.id, %{provider_id: ctx.provider.id})

      agent =
        Map.put(ctx.agent, :media_provider_id, mp.id)

      result = MediaProviders.resolve_media_provider(agent)
      assert result.id == mp.id
    end
  end
end
