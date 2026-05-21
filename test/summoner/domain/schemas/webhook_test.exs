defmodule Summoner.Domain.Schemas.WebhookTest do
  use Summoner.DataCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  alias Summoner.Domain.Schemas.Webhook

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)
    %{workspace: workspace, agent: agent}
  end

  describe "changeset/2" do
    test "valid changeset with required fields", %{workspace: ws, agent: agent} do
      changeset =
        Webhook.changeset(%Webhook{}, %{
          "name" => "my-webhook",
          "target_type" => "agent",
          "target_id" => agent.id,
          "auth_mode" => "public",
          "response_mode" => "async",
          "workspace_id" => ws.id
        })

      assert changeset.valid?,
             "Expected valid changeset, got errors: #{inspect(changeset.errors)}"
    end

    test "requires name", %{agent: agent} do
      changeset =
        Webhook.changeset(%Webhook{}, %{
          "target_type" => "agent",
          "target_id" => agent.id,
          "auth_mode" => "public",
          "response_mode" => "async"
        })

      refute changeset.valid?
      assert errors_on(changeset)[:name]
    end

    test "requires hmac_secret_id when auth_mode is hmac", %{workspace: ws, agent: agent} do
      changeset =
        Webhook.changeset(%Webhook{}, %{
          "name" => "hmac-webhook",
          "target_type" => "agent",
          "target_id" => agent.id,
          "auth_mode" => "hmac",
          "response_mode" => "async",
          "workspace_id" => ws.id
        })

      refute changeset.valid?
      assert errors_on(changeset)[:hmac_secret_id]
    end

    test "rejects hmac_secret_id when auth_mode is public", %{workspace: ws, agent: agent} do
      changeset =
        Webhook.changeset(%Webhook{}, %{
          "name" => "public-webhook",
          "target_type" => "agent",
          "target_id" => agent.id,
          "auth_mode" => "public",
          "response_mode" => "async",
          "workspace_id" => ws.id,
          "hmac_secret_id" => Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert errors_on(changeset)[:hmac_secret_id]
    end

    test "validates rate_limit_rpm range" do
      changeset =
        Webhook.changeset(%Webhook{}, %{
          "name" => "test",
          "target_type" => "agent",
          "target_id" => Ecto.UUID.generate(),
          "auth_mode" => "public",
          "response_mode" => "async",
          "rate_limit_rpm" => 0
        })

      refute changeset.valid?
      assert errors_on(changeset)[:rate_limit_rpm]
    end

    test "validates timeout_s range" do
      changeset =
        Webhook.changeset(%Webhook{}, %{
          "name" => "test",
          "target_type" => "agent",
          "target_id" => Ecto.UUID.generate(),
          "auth_mode" => "public",
          "response_mode" => "async",
          "timeout_s" => 9999
        })

      refute changeset.valid?
      assert errors_on(changeset)[:timeout_s]
    end
  end
end
