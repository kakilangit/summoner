defmodule SummonerWeb.Plugs.RateLimitTest do
  use Summoner.DataCase

  import Plug.Conn

  alias Summoner.Domain.Schemas.AccessToken
  alias SummonerWeb.Plugs.RateLimit

  defp build_conn_with_token(rpm) do
    token = %AccessToken{
      id: elem(Nulid.generate(), 1),
      rate_limit_rpm: rpm
    }

    :get
    |> Plug.Test.conn("/test")
    |> assign(:current_token, token)
  end

  test "passes through when under limit" do
    conn =
      build_conn_with_token(100)
      |> RateLimit.call(RateLimit.init([]))

    refute conn.halted
  end

  test "returns 429 when over limit" do
    conn = build_conn_with_token(1)

    # First request should pass
    conn1 = RateLimit.call(conn, RateLimit.init([]))
    refute conn1.halted

    # Second request with same token should be rate limited
    conn2 = RateLimit.call(conn, RateLimit.init([]))
    assert conn2.status == 429
    assert conn2.halted
  end

  test "sets x-ratelimit-limit and x-ratelimit-remaining headers" do
    conn =
      build_conn_with_token(100)
      |> RateLimit.call(RateLimit.init([]))

    assert get_resp_header(conn, "x-ratelimit-limit") == ["100"]
    [remaining] = get_resp_header(conn, "x-ratelimit-remaining")
    assert String.to_integer(remaining) >= 0
  end

  test "skips rate limiting when no token assigned" do
    conn =
      :get
      |> Plug.Test.conn("/test")
      |> RateLimit.call(RateLimit.init([]))

    refute conn.halted
  end
end
