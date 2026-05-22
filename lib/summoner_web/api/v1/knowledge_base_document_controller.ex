defmodule SummonerWeb.API.V1.KnowledgeBaseDocumentController do
  use SummonerWeb, :controller

  alias Summoner.Ports.DocumentParser
  alias Summoner.Ports.Persistence.KnowledgeBases

  @max_file_size 50 * 1024 * 1024

  def create(conn, %{"knowledge_base_id" => kb_id} = params) do
    workspace = conn.assigns.workspace
    kb = KnowledgeBases.get_knowledge_base!(workspace.id, kb_id)

    case params do
      %{
        "file" => %Plug.Upload{
          path: path,
          filename: filename,
          content_type: content_type
        }
      } ->
        with {:ok, binary} <- File.read(path),
             :ok <- validate_size(binary),
             :ok <- validate_type(content_type),
             {:ok, _parsed} <- DocumentParser.parse(binary, content_type),
             :ok <- store_file(kb, filename, binary) do
          hash =
            :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

          file_hashes = Map.put(kb.file_hashes || %{}, filename, hash)
          doc_count = map_size(file_hashes)

          KnowledgeBases.update_status(kb, %{
            file_hashes: file_hashes,
            document_count: doc_count
          })

          conn
          |> put_status(:created)
          |> json(%{
            filename: filename,
            content_type: content_type,
            size: byte_size(binary),
            hash: hash
          })
        else
          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: to_string(reason)})
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "file parameter required"})
    end
  end

  def delete(conn, %{"knowledge_base_id" => kb_id, "filename" => filename}) do
    workspace = conn.assigns.workspace
    kb = KnowledgeBases.get_knowledge_base!(workspace.id, kb_id)

    upload_dir = upload_path(kb)
    file_path = Path.join(upload_dir, filename)

    if File.exists?(file_path) do
      File.rm!(file_path)
      file_hashes = Map.delete(kb.file_hashes || %{}, filename)
      doc_count = map_size(file_hashes)

      KnowledgeBases.update_status(kb, %{
        file_hashes: file_hashes,
        document_count: doc_count
      })

      conn |> put_status(:ok) |> json(%{deleted: filename})
    else
      conn |> put_status(:not_found) |> json(%{error: "file not found"})
    end
  end

  def index(conn, %{"knowledge_base_id" => kb_id}) do
    workspace = conn.assigns.workspace
    kb = KnowledgeBases.get_knowledge_base!(workspace.id, kb_id)

    upload_dir = upload_path(kb)

    files =
      if File.dir?(upload_dir) do
        upload_dir
        |> File.ls!()
        |> Enum.map(fn name ->
          path = Path.join(upload_dir, name)
          stat = File.stat!(path)

          %{
            filename: name,
            size: stat.size,
            hash: Map.get(kb.file_hashes || %{}, name)
          }
        end)
      else
        []
      end

    json(conn, %{items: files})
  end

  defp validate_size(binary) when byte_size(binary) > @max_file_size,
    do: {:error, "file exceeds maximum size of 50MB"}

  defp validate_size(_), do: :ok

  defp validate_type(content_type) do
    if content_type in DocumentParser.supported_types() do
      :ok
    else
      {:error, "unsupported file type: #{content_type}"}
    end
  end

  defp store_file(kb, filename, binary) do
    dir = upload_path(kb)
    File.mkdir_p!(dir)
    File.write(Path.join(dir, filename), binary)
  end

  defp upload_path(kb) do
    Path.join([
      Application.app_dir(:summoner, "priv"),
      "uploads",
      "knowledge_bases",
      kb.id
    ])
  end
end
