defmodule SummonerWeb.Plugs.RateLimit do
  @moduledoc """
  Simple per-token rate limiting using ETS.

  Tracks request counts per token per minute window. When the limit is
  exceeded, returns 429 with a `Retry-After` header.

  The rate limit is read from the token's `rate_limit_rpm` field.
  Requires `SummonerWeb.Plugs.TokenAuth` to have run first.
  """

  import Plug.Conn

  @behaviour Plug
  @table :summoner_rate_limits

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    ensure_table()

    case conn.assigns[:current_token] do
      nil ->
        # No token assigned — skip rate limiting (auth plug will handle)
        conn

      token ->
        window = current_window()
        key = {token.id, window}
        limit = token.rate_limit_rpm || 100

        count = increment_counter(key)

        if count > limit do
          seconds_remaining = 60 - rem(System.system_time(:second), 60)

          conn
          |> put_resp_header("retry-after", to_string(seconds_remaining))
          |> put_resp_content_type("application/json")
          |> send_resp(
            429,
            Jason.encode!(%{
              error: %{
                code: "rate_limited",
                message: "Rate limit exceeded. Limit: #{limit} requests per minute.",
                retry_after: seconds_remaining
              }
            })
          )
          |> halt()
        else
          conn
          |> put_resp_header("x-ratelimit-limit", to_string(limit))
          |> put_resp_header("x-ratelimit-remaining", to_string(max(limit - count, 0)))
        end
    end
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:public, :named_table, :set, {:write_concurrency, true}])
    end
  end

  defp current_window do
    div(System.system_time(:second), 60)
  end

  defp increment_counter(key) do
    :ets.update_counter(@table, key, {2, 1}, {key, 0})
  rescue
    ArgumentError ->
      ensure_table()
      :ets.update_counter(@table, key, {2, 1}, {key, 0})
  end
end
