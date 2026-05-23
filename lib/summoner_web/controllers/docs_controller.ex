defmodule SummonerWeb.DocsController do
  use SummonerWeb, :controller

  @index Application.app_dir(:summoner, "priv/static/docs/index.html")

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, @index)
  end
end
