defmodule SummonerWeb.Plugs.TokenAuthTest do
  use Summoner.DataCase

  import Plug.Conn

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures
  import Summoner.Adapters.Persistence.AccessTokensFixtures

  alias Summoner.Domain.Schemas.AccessToken
  alias SummonerWeb.Plugs.TokenAuth

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    token = access_token_fixture(workspace.id, %{scopes: ["api"]})
    %{workspace: workspace, token: token, plaintext: token.token}
  end

  defp build_conn(workspace_id, bearer_token) do
    :get
    |> Plug.Test.conn("/api/v1/workspaces/#{workspace_id}/test")
    |> Map.put(:params, %{"workspace_id" => workspace_id})
    |> put_req_header("authorization", "Bearer #{bearer_token}")
  end

  test "assigns current_token and current_workspace_id on valid token", %{
    workspace: workspace,
    plaintext: plaintext
  } do
    conn =
      workspace.id
      |> build_conn(plaintext)
      |> TokenAuth.call(TokenAuth.init(required_scope: "api"))

    assert conn.assigns[:current_token].id != nil
    assert conn.assigns[:current_workspace_id] == workspace.id
    refute conn.halted
  end

  test "returns 401 when no Authorization header", %{workspace: workspace} do
    conn =
      :get
      |> Plug.Test.conn("/api/v1/workspaces/#{workspace.id}/test")
      |> Map.put(:params, %{"workspace_id" => workspace.id})
      |> TokenAuth.call(TokenAuth.init(required_scope: "api"))

    assert conn.status == 401
    assert conn.halted
  end

  test "returns 401 for invalid token", %{workspace: workspace} do
    conn =
      workspace.id
      |> build_conn("shk_invalid_token")
      |> TokenAuth.call(TokenAuth.init(required_scope: "api"))

    assert conn.status == 401
    assert conn.halted
  end

  test "returns 403 when token lacks required scope", %{
    workspace: workspace,
    plaintext: plaintext
  } do
    conn =
      workspace.id
      |> build_conn(plaintext)
      |> TokenAuth.call(TokenAuth.init(required_scope: "a2a"))

    assert conn.status == 403
    assert conn.halted
  end

  test "returns 401 for expired token", %{workspace: workspace} do
    token = access_token_fixture(workspace.id, %{scopes: ["api"]})

    # Set expires_at in the past directly via Repo
    expired_at = DateTime.add(DateTime.utc_now(), -3600, :second)

    Repo.update_all(
      from(t in AccessToken, where: t.id == ^token.id),
      set: [expires_at: expired_at]
    )

    conn =
      workspace.id
      |> build_conn(token.token)
      |> TokenAuth.call(TokenAuth.init(required_scope: "api"))

    assert conn.status == 401
    assert conn.halted
  end
end
