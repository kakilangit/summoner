defmodule Summoner.Adapters.Persistence.AccessTokensTest do
  use Summoner.DataCase

  alias Summoner.Adapters.Persistence.AccessTokens
  alias Summoner.Domain.Schemas.AccessToken

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures
  import Summoner.Adapters.Persistence.AccessTokensFixtures

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    %{workspace: workspace}
  end

  describe "create_token/1" do
    test "creates token with valid attrs, returns plaintext starting with shk_", %{
      workspace: workspace
    } do
      {:ok, token} =
        AccessTokens.create_token(%{
          label: "my-token",
          workspace_id: workspace.id,
          scopes: ["api"],
          rate_limit_rpm: 100
        })

      assert token.label == "my-token"
      assert token.workspace_id == workspace.id
      assert token.scopes == ["api"]
      assert token.rate_limit_rpm == 100
      assert String.starts_with?(token.token, "shk_")
      assert token.token_hash != nil
    end

    test "requires label", %{workspace: workspace} do
      {:error, changeset} =
        AccessTokens.create_token(%{
          workspace_id: workspace.id,
          scopes: ["api"]
        })

      assert %{label: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires at least one scope (empty list fails validation)", %{workspace: workspace} do
      # On create, empty scopes matches the default so validate_change won't fire.
      # But on update from a non-empty value, it does.
      token = access_token_fixture(workspace.id, %{scopes: ["api"]})

      {:error, changeset} = AccessTokens.update_token(token, %{scopes: []})
      assert %{scopes: [_]} = errors_on(changeset)
    end

    test "rejects invalid scope names", %{workspace: workspace} do
      {:error, changeset} =
        AccessTokens.create_token(%{
          label: "bad-scope",
          workspace_id: workspace.id,
          scopes: ["invalid_scope"]
        })

      assert %{scopes: [_]} = errors_on(changeset)
    end

    test "validates rate_limit_rpm > 0 and <= 10_000", %{workspace: workspace} do
      {:error, changeset_zero} =
        AccessTokens.create_token(%{
          label: "zero-rpm",
          workspace_id: workspace.id,
          scopes: ["api"],
          rate_limit_rpm: 0
        })

      assert %{rate_limit_rpm: [_]} = errors_on(changeset_zero)

      {:error, changeset_over} =
        AccessTokens.create_token(%{
          label: "over-rpm",
          workspace_id: workspace.id,
          scopes: ["api"],
          rate_limit_rpm: 10_001
        })

      assert %{rate_limit_rpm: [_]} = errors_on(changeset_over)
    end
  end

  describe "list_tokens/1,2" do
    test "lists active tokens for workspace (excludes revoked by default)", %{
      workspace: workspace
    } do
      token = access_token_fixture(workspace.id)
      revoked = access_token_fixture(workspace.id, %{label: "revoked"})
      {:ok, _} = AccessTokens.revoke_token(revoked)

      tokens = AccessTokens.list_tokens(workspace.id)
      ids = Enum.map(tokens, & &1.id)

      assert token.id in ids
      refute revoked.id in ids
    end

    test "lists including revoked when include_revoked: true", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      revoked = access_token_fixture(workspace.id, %{label: "revoked"})
      {:ok, _} = AccessTokens.revoke_token(revoked)

      tokens = AccessTokens.list_tokens(workspace.id, include_revoked: true)
      ids = Enum.map(tokens, & &1.id)

      assert token.id in ids
      assert revoked.id in ids
    end

    test "returns empty for other workspace", %{workspace: workspace} do
      _token = access_token_fixture(workspace.id)

      other_scope = user_scope_fixture()
      other_workspace = workspace_fixture(other_scope)

      assert AccessTokens.list_tokens(other_workspace.id) == []
    end
  end

  describe "get_token!/2" do
    test "gets token by workspace and id", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      fetched = AccessTokens.get_token!(workspace.id, token.id)
      assert fetched.id == token.id
    end

    test "raises for wrong workspace", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)

      other_scope = user_scope_fixture()
      other_workspace = workspace_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn ->
        AccessTokens.get_token!(other_workspace.id, token.id)
      end
    end

    test "raises for nonexistent id", %{workspace: workspace} do
      assert_raise Ecto.NoResultsError, fn ->
        AccessTokens.get_token!(workspace.id, elem(Nulid.generate(), 1))
      end
    end
  end

  describe "revoke_token/1" do
    test "sets revoked_at", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      assert is_nil(token.revoked_at)

      {:ok, revoked} = AccessTokens.revoke_token(token)
      assert revoked.revoked_at != nil
    end

    test "revoked token excluded from default list", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      {:ok, _} = AccessTokens.revoke_token(token)

      tokens = AccessTokens.list_tokens(workspace.id)
      refute Enum.any?(tokens, &(&1.id == token.id))
    end
  end

  describe "update_token/2" do
    test "updates label", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      {:ok, updated} = AccessTokens.update_token(token, %{label: "new-label"})
      assert updated.label == "new-label"
    end

    test "updates scopes", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      {:ok, updated} = AccessTokens.update_token(token, %{scopes: ["api", "webhook"]})
      assert updated.scopes == ["api", "webhook"]
    end

    test "updates rate_limit_rpm", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      {:ok, updated} = AccessTokens.update_token(token, %{rate_limit_rpm: 500})
      assert updated.rate_limit_rpm == 500
    end

    test "rejects empty scopes on update", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      {:error, changeset} = AccessTokens.update_token(token, %{scopes: []})
      assert %{scopes: [_]} = errors_on(changeset)
    end
  end

  describe "verify_token/2 (workspace-scoped, no scope check)" do
    test "verifies valid plaintext token", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      {:ok, verified} = AccessTokens.verify_token(token.token, workspace_id: workspace.id)
      assert verified.id == token.id
    end

    test "increments request_count on verify", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      {:ok, _} = AccessTokens.verify_token(token.token, workspace_id: workspace.id)

      refreshed = AccessTokens.get_token!(workspace.id, token.id)
      assert refreshed.request_count == 1
    end

    test "returns error for invalid plaintext", %{workspace: workspace} do
      _token = access_token_fixture(workspace.id)

      assert {:error, :invalid} =
               AccessTokens.verify_token("shk_bogus", workspace_id: workspace.id)
    end

    test "returns error for revoked token", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      {:ok, _} = AccessTokens.revoke_token(token)

      assert {:error, :invalid} =
               AccessTokens.verify_token(token.token, workspace_id: workspace.id)
    end
  end

  describe "verify_token/2 (workspace-scoped, with scope)" do
    test "verifies with matching scope", %{workspace: workspace} do
      token = access_token_fixture(workspace.id, %{scopes: ["api"]})

      {:ok, verified} =
        AccessTokens.verify_token(token.token, scope: "api", workspace_id: workspace.id)

      assert verified.id == token.id
    end

    test "returns :wrong_scope for mismatched scope", %{workspace: workspace} do
      token = access_token_fixture(workspace.id, %{scopes: ["api"]})

      assert {:error, :wrong_scope} =
               AccessTokens.verify_token(token.token, scope: "a2a", workspace_id: workspace.id)
    end

    test "returns :ok when token has all scope", %{workspace: workspace} do
      token = access_token_fixture(workspace.id, %{scopes: ["all"]})

      {:ok, verified} =
        AccessTokens.verify_token(token.token, scope: "webhook", workspace_id: workspace.id)

      assert verified.id == token.id
    end

    test "returns :expired for expired token", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      expired_at = DateTime.add(DateTime.utc_now(), -3600, :second)

      Repo.update_all(
        from(t in AccessToken, where: t.id == ^token.id),
        set: [expires_at: expired_at]
      )

      assert {:error, :expired} =
               AccessTokens.verify_token(token.token, scope: "api", workspace_id: workspace.id)
    end
  end

  describe "verify_token/2 (global, no scope check)" do
    test "verifies valid plaintext without workspace", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      assert {:ok, verified} = AccessTokens.verify_token(token.token, [])
      assert verified.id == token.id
      assert verified.workspace_id == workspace.id
    end

    test "returns error for invalid plaintext" do
      assert {:error, :invalid} = AccessTokens.verify_token("shk_bogus", [])
    end
  end

  describe "verify_token/2 (global, with scope)" do
    test "verifies with matching scope", %{workspace: workspace} do
      token = access_token_fixture(workspace.id, %{scopes: ["api"]})
      assert {:ok, verified} = AccessTokens.verify_token(token.token, scope: "api")
      assert verified.id == token.id
    end

    test "returns :wrong_scope for mismatched scope", %{workspace: workspace} do
      token = access_token_fixture(workspace.id, %{scopes: ["api"]})
      assert {:error, :wrong_scope} = AccessTokens.verify_token(token.token, scope: "a2a")
    end

    test "returns :ok when token has all scope", %{workspace: workspace} do
      token = access_token_fixture(workspace.id, %{scopes: ["all"]})
      assert {:ok, _} = AccessTokens.verify_token(token.token, scope: "webhook")
    end

    test "returns :expired for expired token", %{workspace: workspace} do
      token = access_token_fixture(workspace.id)
      expired_at = DateTime.add(DateTime.utc_now(), -3600, :second)

      Repo.update_all(
        from(t in AccessToken, where: t.id == ^token.id),
        set: [expires_at: expired_at]
      )

      assert {:error, :expired} = AccessTokens.verify_token(token.token, scope: "api")
    end
  end

  describe "AccessToken schema" do
    test "active?/1 returns true for non-revoked, non-expired" do
      token = %AccessToken{revoked_at: nil, expires_at: nil}
      assert AccessToken.active?(token)
    end

    test "active?/1 returns false for revoked" do
      token = %AccessToken{revoked_at: DateTime.utc_now(), expires_at: nil}
      refute AccessToken.active?(token)
    end

    test "active?/1 returns false for expired" do
      token = %AccessToken{
        revoked_at: nil,
        expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)
      }

      refute AccessToken.active?(token)
    end

    test "has_scope?/2 returns true for matching scope" do
      token = %AccessToken{scopes: ["api", "webhook"]}
      assert AccessToken.has_scope?(token, "api")
    end

    test "has_scope?/2 returns true when token has all" do
      token = %AccessToken{scopes: ["all"]}
      assert AccessToken.has_scope?(token, "webhook")
    end

    test "has_scope?/2 returns false for missing scope" do
      token = %AccessToken{scopes: ["api"]}
      refute AccessToken.has_scope?(token, "a2a")
    end
  end
end
