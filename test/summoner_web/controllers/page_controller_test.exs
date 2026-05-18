defmodule SummonerWeb.PageControllerTest do
  use SummonerWeb.ConnCase

  test "GET / redirects unauthenticated user to log in", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "GET / redirects authenticated user to workspaces", %{conn: conn} do
    conn = conn |> log_in_user(Summoner.AccountsFixtures.user_fixture()) |> get(~p"/")
    assert redirected_to(conn) == ~p"/guilds"
  end
end
