defmodule Summoner.FileSystem do
  @moduledoc """
  Context for workspace file system operations.

  All paths are sandboxed within the workspace directory.
  Prevents path traversal and symlink escapes.
  """

  alias Summoner.Workspaces

  @max_file_size 10 * 1_024 * 1_024
  @max_entries 1_000

  @type entry :: %{
          name: String.t(),
          type: :file | :directory,
          size: non_neg_integer(),
          modified_at: NaiveDateTime.t()
        }

  @doc """
  Lists entries in a workspace subdirectory.

  Returns `{:ok, entries}` or `{:error, reason}`.
  """
  @spec list_dir(String.t(), String.t()) :: {:ok, [entry()]} | {:error, atom()}
  def list_dir(workspace_id, relative_path \\ "") do
    with {:ok, full_path} <- resolve_path(workspace_id, relative_path),
         {:ok, names} <- safe_ls(full_path) do
      entries =
        names
        |> Enum.take(@max_entries)
        |> Enum.map(&build_entry(full_path, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(fn e -> {e.type == :file, e.name} end)

      {:ok, entries}
    end
  end

  @doc """
  Reads a file's content within the workspace.

  Returns `{:ok, content}` or `{:error, reason}`.
  Refuses to read files larger than #{div(@max_file_size, 1_024 * 1_024)} MB.
  """
  @spec read_file(String.t(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def read_file(workspace_id, relative_path) do
    with {:ok, full_path} <- resolve_path(workspace_id, relative_path),
         :ok <- ensure_file(full_path),
         :ok <- check_size(full_path) do
      File.read(full_path)
    end
  end

  @doc """
  Writes content to a file within the workspace.

  Creates parent directories as needed.
  """
  @spec write_file(String.t(), String.t(), String.t()) :: :ok | {:error, atom()}
  def write_file(workspace_id, relative_path, content) do
    with {:ok, full_path} <- resolve_path(workspace_id, relative_path),
         :ok <- ensure_parent_exists(full_path) do
      File.write(full_path, content)
    end
  end

  @doc """
  Creates a directory within the workspace.
  """
  @spec mkdir(String.t(), String.t()) :: :ok | {:error, atom()}
  def mkdir(workspace_id, relative_path) do
    with {:ok, full_path} <- resolve_path(workspace_id, relative_path) do
      File.mkdir_p(full_path)
    end
  end

  @doc """
  Deletes a file or empty directory within the workspace.
  """
  @spec delete(String.t(), String.t()) :: :ok | {:error, atom()}
  def delete(workspace_id, relative_path) do
    with {:ok, full_path} <- resolve_path(workspace_id, relative_path) do
      case File.stat(full_path) do
        {:ok, %{type: :directory}} -> File.rmdir(full_path)
        {:ok, %{type: :regular}} -> File.rm(full_path)
        {:ok, _} -> {:error, :unsupported_type}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Recursively deletes a file or directory within the workspace.
  """
  @spec delete_recursive(String.t(), String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  def delete_recursive(workspace_id, relative_path) do
    with {:ok, full_path} <- resolve_path(workspace_id, relative_path) do
      File.rm_rf(full_path)
    end
  end

  @doc """
  Renames a file or directory within the workspace.
  """
  @spec rename(String.t(), String.t(), String.t()) :: :ok | {:error, atom()}
  def rename(workspace_id, from_path, to_path) do
    with {:ok, full_from} <- resolve_path(workspace_id, from_path),
         {:ok, full_to} <- resolve_path(workspace_id, to_path) do
      File.rename(full_from, full_to)
    end
  end

  @doc """
  Returns the absolute path for streaming a file download.
  """
  @spec download_path(String.t(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def download_path(workspace_id, relative_path) do
    with {:ok, full_path} <- resolve_path(workspace_id, relative_path),
         :ok <- ensure_file(full_path) do
      {:ok, full_path}
    end
  end

  @doc """
  Creates a tar.gz archive of the workspace directory.

  Returns `{:ok, archive_path}` where archive_path is a temp file.
  Caller is responsible for cleanup.
  """
  @spec archive(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def archive(workspace_id) do
    root = Workspaces.workspace_dir(workspace_id)
    archive_path = Path.join(System.tmp_dir!(), "workspace_#{workspace_id}.tar.gz")

    case System.cmd("tar", ["-czf", archive_path, "-C", root, "."], stderr_to_stdout: true) do
      {_, 0} -> {:ok, archive_path}
      {_, _} -> {:error, :archive_failed}
    end
  end

  @doc """
  Saves an uploaded file to the workspace directory.
  """
  @spec save_upload(String.t(), String.t(), String.t()) :: :ok | {:error, atom()}
  def save_upload(workspace_id, relative_dir, tmp_path) do
    filename = Path.basename(tmp_path)

    with {:ok, dest_dir} <- resolve_path(workspace_id, relative_dir),
         :ok <- File.mkdir_p(dest_dir) do
      dest = Path.join(dest_dir, filename)
      File.cp(tmp_path, dest)
    end
  end

  # -------------------------------------------------------------------
  # Private — path safety
  # -------------------------------------------------------------------

  defp resolve_path(workspace_id, relative_path) do
    root = Workspaces.workspace_dir(workspace_id)
    # Normalize and join
    candidate = Path.join(root, relative_path) |> Path.expand()

    # Ensure the resolved path is within the workspace root
    if String.starts_with?(candidate, root) do
      {:ok, candidate}
    else
      {:error, :path_traversal}
    end
  end

  defp safe_ls(path) do
    case File.ls(path) do
      {:ok, names} -> {:ok, Enum.reject(names, &String.starts_with?(&1, "."))}
      {:error, :enoent} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_entry(parent, name) do
    path = Path.join(parent, name)

    case File.stat(path) do
      {:ok, %{type: type, size: size, mtime: mtime}} when type in [:regular, :directory] ->
        %{
          name: name,
          type: if(type == :regular, do: :file, else: :directory),
          size: size,
          modified_at: NaiveDateTime.from_erl!(mtime)
        }

      _ ->
        nil
    end
  end

  defp ensure_file(path) do
    case File.stat(path) do
      {:ok, %{type: :regular}} -> :ok
      {:ok, _} -> {:error, :not_a_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_file_size -> :ok
      {:ok, _} -> {:error, :file_too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_parent_exists(path) do
    path |> Path.dirname() |> File.mkdir_p()
  end
end
