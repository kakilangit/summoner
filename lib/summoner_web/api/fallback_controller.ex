defmodule SummonerWeb.API.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  Used as `action_fallback` in API controllers to handle error tuples
  returned from port/adapter calls.
  """

  use SummonerWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(SummonerWeb.API.ErrorJSON)
    |> render("422.json", changeset: changeset)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(SummonerWeb.API.ErrorJSON)
    |> render("404.json")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:forbidden)
    |> put_view(SummonerWeb.API.ErrorJSON)
    |> render("403.json")
  end
end
