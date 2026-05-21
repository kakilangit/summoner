defmodule SummonerWeb.ArtifactController do
  @moduledoc "Handles artifact file downloads."

  use SummonerWeb, :controller

  alias Summoner.Domain.Schemas.Scope
  alias Summoner.Ports.Persistence.Artifacts

  def download(conn, %{"id" => id, "workspace_id" => workspace_id}) do
    scope = %Scope{user: conn.assigns[:current_user]}
    artifact = Artifacts.get_artifact!(scope, workspace_id, id)

    extension = mime_to_extension(artifact.content_type)
    filename = "#{artifact.name}.#{extension}"

    conn
    |> put_resp_content_type(artifact.content_type || "text/plain")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, artifact.content || "")
  end

  defp mime_to_extension("text/markdown"), do: "md"
  defp mime_to_extension("text/x-elixir"), do: "ex"
  defp mime_to_extension("text/x-python"), do: "py"
  defp mime_to_extension("text/javascript"), do: "js"
  defp mime_to_extension("text/typescript"), do: "ts"
  defp mime_to_extension("application/json"), do: "json"
  defp mime_to_extension("text/css"), do: "css"
  defp mime_to_extension("text/html"), do: "html"
  defp mime_to_extension("text/x-rust"), do: "rs"
  defp mime_to_extension("text/x-go"), do: "go"
  defp mime_to_extension("text/plain"), do: "txt"
  defp mime_to_extension(_), do: "txt"
end
