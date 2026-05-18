defmodule Summoner.SecretsTest do
  use Summoner.DataCase

  alias Summoner.Secrets

  import Summoner.AccountsFixtures
  import Summoner.WorkspacesFixtures

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)

    %{scope: scope, workspace: workspace}
  end

  describe "create_secret/2" do
    test "creates an encrypted secret", ctx do
      assert {:ok, secret} =
               Secrets.create_secret(ctx.scope, %{
                 name: "GITHUB_TOKEN",
                 encrypted_value: "ghp_abc123",
                 workspace_id: ctx.workspace.id
               })

      assert secret.name == "GITHUB_TOKEN"
      assert secret.encrypted_value == "ghp_abc123"
    end

    test "rejects invalid name format", ctx do
      assert {:error, changeset} =
               Secrets.create_secret(ctx.scope, %{
                 name: "lowercase",
                 encrypted_value: "value",
                 workspace_id: ctx.workspace.id
               })

      assert errors_on(changeset).name
    end

    test "rejects duplicate name in same workspace", ctx do
      {:ok, _} =
        Secrets.create_secret(ctx.scope, %{
          name: "MY_SECRET",
          encrypted_value: "v1",
          workspace_id: ctx.workspace.id
        })

      assert {:error, changeset} =
               Secrets.create_secret(ctx.scope, %{
                 name: "MY_SECRET",
                 encrypted_value: "v2",
                 workspace_id: ctx.workspace.id
               })

      assert errors_on(changeset).workspace_id
    end
  end

  describe "list_secrets/2" do
    test "lists secrets for a workspace", ctx do
      {:ok, _} =
        Secrets.create_secret(ctx.scope, %{
          name: "SECRET_A",
          encrypted_value: "a",
          workspace_id: ctx.workspace.id
        })

      {:ok, _} =
        Secrets.create_secret(ctx.scope, %{
          name: "SECRET_B",
          encrypted_value: "b",
          workspace_id: ctx.workspace.id
        })

      secrets = Secrets.list_secrets(ctx.scope, ctx.workspace.id, ctx.workspace.tenant_id)
      assert length(secrets) == 2
      assert Enum.map(secrets, & &1.name) == ["SECRET_A", "SECRET_B"]
    end
  end

  describe "update_secret/3" do
    test "updates secret value", ctx do
      {:ok, secret} =
        Secrets.create_secret(ctx.scope, %{
          name: "MY_KEY",
          encrypted_value: "old_value",
          workspace_id: ctx.workspace.id
        })

      assert {:ok, updated} =
               Secrets.update_secret(ctx.scope, secret, %{encrypted_value: "new_value"})

      assert updated.encrypted_value == "new_value"
    end
  end

  describe "delete_secret/2" do
    test "deletes a secret", ctx do
      {:ok, secret} =
        Secrets.create_secret(ctx.scope, %{
          name: "TO_DELETE",
          encrypted_value: "val",
          workspace_id: ctx.workspace.id
        })

      assert {:ok, _} = Secrets.delete_secret(ctx.scope, secret)
      assert Secrets.list_secrets(ctx.scope, ctx.workspace.id, ctx.workspace.tenant_id) == []
    end
  end

  describe "resolve/2" do
    test "resolves secret references", ctx do
      {:ok, _} =
        Secrets.create_secret(ctx.scope, %{
          name: "GIT_TOKEN",
          encrypted_value: "ghp_secret",
          workspace_id: ctx.workspace.id
        })

      env = %{"GIT_TOKEN" => "$GIT_TOKEN", "HOME" => "/home/user"}

      assert {:ok, resolved} = Secrets.resolve(ctx.workspace.id, ctx.workspace.tenant_id, env)
      assert resolved["GIT_TOKEN"] == "ghp_secret"
      assert resolved["HOME"] == "/home/user"
    end

    test "returns error for missing secrets", ctx do
      env = %{"TOKEN" => "$MISSING_SECRET"}

      assert {:error, {:missing_secrets, ["MISSING_SECRET"]}} =
               Secrets.resolve(ctx.workspace.id, ctx.workspace.tenant_id, env)
    end

    test "passes through map with no references", ctx do
      env = %{"HOME" => "/home/user", "PATH" => "/usr/bin"}

      assert {:ok, ^env} = Secrets.resolve(ctx.workspace.id, ctx.workspace.tenant_id, env)
    end

    test "handles nil", ctx do
      assert {:ok, %{}} = Secrets.resolve(ctx.workspace.id, ctx.workspace.tenant_id, nil)
    end
  end

  describe "resolve_value/2" do
    test "resolves a single secret reference", ctx do
      {:ok, _} =
        Secrets.create_secret(ctx.scope, %{
          name: "API_KEY",
          encrypted_value: "sk-123",
          workspace_id: ctx.workspace.id
        })

      assert {:ok, "sk-123"} =
               Secrets.resolve_value(ctx.workspace.id, ctx.workspace.tenant_id, "$API_KEY")
    end

    test "passes through non-reference values", ctx do
      assert {:ok, "plain_value"} =
               Secrets.resolve_value(ctx.workspace.id, ctx.workspace.tenant_id, "plain_value")
    end

    test "returns error for missing secret", ctx do
      assert {:error, {:missing_secret, "NOPE"}} =
               Secrets.resolve_value(ctx.workspace.id, ctx.workspace.tenant_id, "$NOPE")
    end

    test "handles nil", _ctx do
      {:ok, id} = Nulid.generate()
      assert {:ok, nil} = Secrets.resolve_value(id, nil, nil)
    end
  end
end
