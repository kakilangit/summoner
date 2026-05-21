defmodule Summoner.Adapters.Persistence.AccessTokensDeleteTest do
  use Summoner.DataCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AccessTokensFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  alias Summoner.Ports.Persistence.AccessTokens

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    %{workspace: workspace}
  end

  describe "delete_token/1" do
    test "deletes a revoked token", %{workspace: ws} do
      token = access_token_fixture(ws.id, ws.tenant_id)
      {:ok, revoked} = AccessTokens.revoke_token(token)
      assert {:ok, _} = AccessTokens.delete_token(revoked)

      assert_raise Ecto.NoResultsError, fn ->
        AccessTokens.get_token!(ws.id, token.id)
      end
    end

    test "refuses to delete an active token", %{workspace: ws} do
      token = access_token_fixture(ws.id, ws.tenant_id)
      assert {:error, :not_revoked} = AccessTokens.delete_token(token)
    end
  end
end
