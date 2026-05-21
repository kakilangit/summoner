defmodule SummonerWeb.API.ErrorJSON do
  @moduledoc "JSON error responses for API endpoints."

  def render("404.json", _assigns) do
    %{error: %{code: "not_found", message: "Resource not found"}}
  end

  def render("400.json", %{reason: reason}) do
    %{error: %{code: "bad_request", message: to_string(reason)}}
  end

  def render("400.json", _assigns) do
    %{error: %{code: "bad_request", message: "Bad request"}}
  end

  def render("422.json", %{changeset: changeset}) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    %{error: %{code: "validation_error", message: "Validation failed", details: errors}}
  end

  def render("422.json", _assigns) do
    %{error: %{code: "validation_error", message: "Unprocessable entity"}}
  end

  def render("500.json", _assigns) do
    %{error: %{code: "internal_error", message: "Internal server error"}}
  end

  def render(template, _assigns) do
    %{error: %{code: "error", message: Phoenix.Controller.status_message_from_template(template)}}
  end
end
