defmodule SummonerWeb.PageController do
  use SummonerWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_scope] do
      redirect(conn, to: ~p"/guilds")
    else
      redirect(conn, to: ~p"/users/log-in")
    end
  end
end
