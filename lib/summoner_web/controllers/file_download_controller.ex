defmodule SummonerWeb.FileDownloadController do
  use SummonerWeb, :controller

  alias Summoner.FileSystem
  alias Summoner.Workspaces

  @doc """
  Downloads a single file from the workspace.
  """
  def download(conn, %{"workspace_id" => workspace_id, "path" => path_parts}) do
    scope = conn.assigns.current_scope
    relative_path = Path.join(path_parts)

    with {:ok, _workspace} <- fetch_workspace(scope, workspace_id),
         {:ok, full_path} <- FileSystem.download_path(workspace_id, relative_path) do
      filename = Path.basename(full_path)

      conn
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_file(200, full_path)
    else
      {:error, :path_traversal} -> send_resp(conn, 403, "Forbidden")
      {:error, :not_a_file} -> send_resp(conn, 400, "Not a file")
      {:error, :enoent} -> send_resp(conn, 404, "Not found")
      {:error, _} -> send_resp(conn, 404, "Not found")
    end
  end

  @doc """
  Downloads the entire workspace as a tar.gz archive.
  """
  def archive(conn, %{"workspace_id" => workspace_id}) do
    scope = conn.assigns.current_scope

    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         {:ok, archive_path} <- FileSystem.archive(workspace_id) do
      filename = "#{workspace.name |> String.replace(~r/[^\w-]/, "_")}.tar.gz"

      conn =
        conn
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> send_file(200, archive_path)

      File.rm(archive_path)
      conn
    else
      {:error, :archive_failed} -> send_resp(conn, 500, "Archive creation failed")
      {:error, _} -> send_resp(conn, 404, "Not found")
    end
  end

  defp fetch_workspace(scope, workspace_id) do
    {:ok, Workspaces.get_workspace!(scope, workspace_id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end
end
