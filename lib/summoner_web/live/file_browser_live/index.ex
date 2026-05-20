defmodule SummonerWeb.FileBrowserLive.Index do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Workspaces
  alias Summoner.Domain.Types.Features
  alias Summoner.Services.FileSystem

  @max_upload_size 50 * 1_024 * 1_024

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Scrolls - #{workspace.name}",
        current_path: "",
        entries: [],
        viewing_file: nil,
        file_content: nil,
        editing: false,
        renaming: nil,
        creating_dir: false,
        delete_target: nil,
        local_mode: Features.local_mode?()
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Scrolls", nil}
        ]
      )
      |> allow_upload(:files,
        accept: :any,
        max_entries: 10,
        max_file_size: @max_upload_size
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    path =
      case params do
        %{"path" => parts} when parts != [] -> Path.join(parts)
        _ -> ""
      end

    socket = load_directory(socket, path)
    {:noreply, socket}
  end

  # -------------------------------------------------------------------
  # Navigation
  # -------------------------------------------------------------------

  @impl true
  def handle_event("navigate", %{"path" => path}, socket) do
    workspace = socket.assigns.workspace
    route = scroll_path(workspace, path)
    {:noreply, push_navigate(socket, to: route)}
  end

  @impl true
  def handle_event("navigate_up", _params, socket) do
    workspace = socket.assigns.workspace
    parent = socket.assigns.current_path |> Path.dirname()
    parent = if parent == ".", do: "", else: parent
    route = scroll_path(workspace, parent)
    {:noreply, push_navigate(socket, to: route)}
  end

  # -------------------------------------------------------------------
  # File viewing / editing
  # -------------------------------------------------------------------

  @impl true
  def handle_event("view_file", %{"path" => path}, socket) do
    workspace_id = socket.assigns.workspace.id

    case FileSystem.read_file(workspace_id, path) do
      {:ok, content} ->
        {:noreply, assign(socket, viewing_file: path, file_content: content, editing: false)}

      {:error, :file_too_large} ->
        {:noreply, put_flash(socket, :error, "File too large to view (max 10 MB).")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not read file.")}
    end
  end

  @impl true
  def handle_event("close_viewer", _params, socket) do
    {:noreply, assign(socket, viewing_file: nil, file_content: nil, editing: false)}
  end

  @impl true
  def handle_event("edit_file", _params, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  @impl true
  def handle_event("save_file", %{"content" => content}, socket) do
    workspace_id = socket.assigns.workspace.id
    path = socket.assigns.viewing_file

    case FileSystem.write_file(workspace_id, path, content) do
      :ok ->
        {:noreply,
         socket
         |> assign(file_content: content, editing: false)
         |> put_flash(:info, "File saved.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not save file.")}
    end
  end

  # -------------------------------------------------------------------
  # File management
  # -------------------------------------------------------------------

  @impl true
  def handle_event("confirm_delete", %{"path" => path}, socket) do
    {:noreply, assign(socket, delete_target: path)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    workspace_id = socket.assigns.workspace.id
    path = socket.assigns.delete_target

    case FileSystem.delete_recursive(workspace_id, path) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(delete_target: nil)
         |> put_flash(:info, "Deleted.")
         |> load_directory(socket.assigns.current_path)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(delete_target: nil)
         |> put_flash(:error, "Could not delete.")}
    end
  end

  @impl true
  def handle_event("start_rename", %{"path" => path}, socket) do
    {:noreply, assign(socket, renaming: path)}
  end

  @impl true
  def handle_event("cancel_rename", _params, socket) do
    {:noreply, assign(socket, renaming: nil)}
  end

  @impl true
  def handle_event("rename", %{"new_name" => new_name}, socket) do
    workspace_id = socket.assigns.workspace.id
    old_path = socket.assigns.renaming
    dir = Path.dirname(old_path)
    new_path = if dir == ".", do: new_name, else: Path.join(dir, new_name)

    case FileSystem.rename(workspace_id, old_path, new_path) do
      :ok ->
        {:noreply,
         socket
         |> assign(renaming: nil)
         |> put_flash(:info, "Renamed.")
         |> load_directory(socket.assigns.current_path)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not rename.")}
    end
  end

  @impl true
  def handle_event("start_create_dir", _params, socket) do
    {:noreply, assign(socket, creating_dir: true)}
  end

  @impl true
  def handle_event("cancel_create_dir", _params, socket) do
    {:noreply, assign(socket, creating_dir: false)}
  end

  @impl true
  def handle_event("create_dir", %{"name" => name}, socket) do
    workspace_id = socket.assigns.workspace.id
    path = Path.join(socket.assigns.current_path, name)

    case FileSystem.mkdir(workspace_id, path) do
      :ok ->
        {:noreply,
         socket
         |> assign(creating_dir: false)
         |> put_flash(:info, "Directory created.")
         |> load_directory(socket.assigns.current_path)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not create directory.")}
    end
  end

  # -------------------------------------------------------------------
  # Upload
  # -------------------------------------------------------------------

  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("upload", _params, socket) do
    workspace_id = socket.assigns.workspace.id
    current_path = socket.assigns.current_path

    uploaded_files =
      consume_uploaded_entries(socket, :files, fn %{path: tmp_path}, entry ->
        dest_dir_path = resolve_upload_dest(workspace_id, current_path)
        dest = Path.join(dest_dir_path, entry.client_name)
        File.mkdir_p!(Path.dirname(dest))
        File.cp!(tmp_path, dest)
        {:ok, entry.client_name}
      end)

    {:noreply,
     socket
     |> put_flash(:info, "Uploaded #{length(uploaded_files)} file(s).")
     |> load_directory(current_path)}
  end

  # -------------------------------------------------------------------
  # Open in file manager (local mode only)
  # -------------------------------------------------------------------

  @impl true
  def handle_event("open_workspace", _params, socket) do
    workspace = socket.assigns.workspace

    case Workspaces.open_workspace_dir(workspace.id) do
      :ok -> {:noreply, socket}
      {:error, msg} -> {:noreply, put_flash(socket, :error, msg)}
    end
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp load_directory(socket, path) do
    workspace_id = socket.assigns.workspace.id

    case FileSystem.list_dir(workspace_id, path) do
      {:ok, entries} ->
        assign(socket,
          current_path: path,
          entries: entries,
          viewing_file: nil,
          file_content: nil,
          editing: false
        )

      {:error, _reason} ->
        socket
        |> assign(current_path: "", entries: [])
        |> put_flash(:error, "Could not read directory.")
    end
  end

  defp resolve_upload_dest(workspace_id, current_path) do
    root = Workspaces.workspace_dir(workspace_id)
    Path.join(root, current_path)
  end

  defp scroll_path(workspace, ""),
    do: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/scrolls"

  defp scroll_path(workspace, path),
    do: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/scrolls/#{path}"

  defp path_breadcrumbs(current_path) do
    parts = current_path |> String.split("/") |> Enum.reject(&(&1 == ""))

    parts
    |> Enum.with_index()
    |> Enum.map(fn {part, idx} ->
      sub_path = parts |> Enum.take(idx + 1) |> Path.join()
      {part, sub_path}
    end)
  end

  defp file_icon(entry) do
    case entry.type do
      :directory -> "hero-folder size-5 text-warning"
      :file -> "hero-document size-5 text-base-content/60"
    end
  end

  defp format_size(size) when size < 1_024, do: "#{size} B"
  defp format_size(size) when size < 1_024 * 1_024, do: "#{Float.round(size / 1_024, 1)} KB"
  defp format_size(size), do: "#{Float.round(size / (1_024 * 1_024), 1)} MB"

  defp text_file?(path) do
    ext = path |> Path.extname() |> String.downcase()

    ext in ~w(.txt .md .ex .exs .erl .hrl .json .yaml .yml .toml .xml .html .css .js .ts
              .sh .bash .zsh .fish .py .rb .rs .go .c .h .cpp .hpp .java .kt .swift
              .sql .graphql .dockerfile .gitignore .env .cfg .ini .conf .log .csv .tsv)
  end

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Header --%>
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Scrolls</h1>
        <div class="flex items-center gap-2">
          <button
            :if={@local_mode}
            phx-click="open_workspace"
            class="btn btn-ghost btn-sm gap-1"
            title="Open in file manager"
          >
            <span class="hero-folder-open size-4"></span> Open
          </button>
          <button phx-click="start_create_dir" class="btn btn-ghost btn-sm gap-1">
            <span class="hero-folder-plus size-4"></span> New Folder
          </button>
        </div>
      </div>

      <%!-- Path breadcrumbs --%>
      <div class="text-sm breadcrumbs">
        <ul>
          <li>
            <button phx-click="navigate" phx-value-path="" class="link link-hover">
              <span class="hero-home size-4"></span>
            </button>
          </li>
          <li :for={{part, sub_path} <- path_breadcrumbs(@current_path)}>
            <button phx-click="navigate" phx-value-path={sub_path} class="link link-hover">
              {part}
            </button>
          </li>
        </ul>
      </div>

      <%!-- Create directory form --%>
      <div :if={@creating_dir} class="flex items-center gap-2 p-3 bg-base-200 rounded-lg">
        <form phx-submit="create_dir" class="flex items-center gap-2 flex-1">
          <input
            type="text"
            name="name"
            placeholder="Directory name"
            class="input input-sm input-bordered flex-1"
            autofocus
            required
          />
          <button type="submit" class="btn btn-primary btn-sm">Create</button>
          <button type="button" phx-click="cancel_create_dir" class="btn btn-ghost btn-sm">
            Cancel
          </button>
        </form>
      </div>

      <%!-- Upload area --%>
      <form phx-change="validate_upload" phx-submit="upload" class="space-y-2">
        <div class="flex items-center gap-2">
          <.live_file_input
            upload={@uploads.files}
            class="file-input file-input-sm file-input-bordered"
          />
          <button
            :if={@uploads.files.entries != []}
            type="submit"
            class="btn btn-primary btn-sm"
          >
            Upload ({length(@uploads.files.entries)})
          </button>
        </div>
        <div :for={entry <- @uploads.files.entries} class="flex items-center gap-2 text-sm">
          <span>{entry.client_name}</span>
          <progress class="progress progress-primary w-20" value={entry.progress} max="100" />
        </div>
      </form>

      <%!-- Go up button --%>
      <button
        :if={@current_path != ""}
        phx-click="navigate_up"
        class="btn btn-ghost btn-sm gap-1"
      >
        <span class="hero-arrow-uturn-left size-4"></span> Up
      </button>

      <%!-- File listing --%>
      <div :if={@entries == []} class="text-center py-12 text-base-content/60">
        <span class="hero-folder-open size-12 mx-auto mb-2 block"></span>
        <p>This directory is empty.</p>
      </div>

      <div :if={@entries != []} class="space-y-1">
        <div
          :for={entry <- @entries}
          class="flex items-center justify-between p-3 bg-base-200 rounded-lg hover:bg-base-300 transition-colors group"
        >
          <div class="flex items-center gap-3 flex-1 min-w-0">
            <span class={file_icon(entry)}></span>

            <%!-- Rename form or clickable name --%>
            <form
              :if={@renaming == entry_path(@current_path, entry.name)}
              phx-submit="rename"
              class="flex items-center gap-2 flex-1"
            >
              <input
                type="text"
                name="new_name"
                value={entry.name}
                class="input input-xs input-bordered flex-1"
                autofocus
              />
              <button type="submit" class="btn btn-xs btn-primary">Save</button>
              <button type="button" phx-click="cancel_rename" class="btn btn-xs btn-ghost">
                Cancel
              </button>
            </form>

            <button
              :if={@renaming != entry_path(@current_path, entry.name) && entry.type == :directory}
              phx-click="navigate"
              phx-value-path={entry_path(@current_path, entry.name)}
              class="link link-hover truncate text-left"
            >
              {entry.name}/
            </button>

            <button
              :if={
                @renaming != entry_path(@current_path, entry.name) && entry.type == :file &&
                  text_file?(entry.name)
              }
              phx-click={
                JS.push("view_file", value: %{path: entry_path(@current_path, entry.name)})
                |> show_confirm("#file-viewer-modal")
              }
              class="link link-hover truncate text-left"
            >
              {entry.name}
            </button>

            <span
              :if={
                @renaming != entry_path(@current_path, entry.name) && entry.type == :file &&
                  !text_file?(entry.name)
              }
              class="truncate"
            >
              {entry.name}
            </span>
          </div>

          <div class="flex items-center gap-2 text-sm text-base-content/60">
            <span :if={entry.type == :file}>{format_size(entry.size)}</span>
            <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
              <button
                phx-click="start_rename"
                phx-value-path={entry_path(@current_path, entry.name)}
                class="btn btn-ghost btn-xs"
                title="Rename"
              >
                <span class="hero-pencil size-3.5"></span>
              </button>
              <.link
                :if={entry.type == :file}
                href={
                  ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/files/download/#{entry_path(@current_path, entry.name)}"
                }
                class="btn btn-ghost btn-xs"
                title="Download"
              >
                <span class="hero-arrow-down-tray size-3.5"></span>
              </.link>
              <button
                phx-click={
                  JS.push("confirm_delete", value: %{path: entry_path(@current_path, entry.name)})
                  |> show_confirm("#delete-modal")
                }
                class="btn btn-ghost btn-xs text-error"
                title="Delete"
              >
                <span class="hero-trash size-3.5"></span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Delete confirmation modal --%>
      <.confirm_modal
        id="delete-modal"
        title="Delete this item?"
        message={"'#{@delete_target && Path.basename(@delete_target)}' will be permanently deleted."}
        on_confirm={JS.push("delete")}
      />

      <%!-- File viewer / editor modal --%>
      <div
        id="file-viewer-modal"
        class="modal"
        role="dialog"
      >
        <div class="modal-box max-w-4xl max-h-[85vh] flex flex-col">
          <div class="flex items-center justify-between mb-4">
            <span class="font-mono text-sm truncate">
              {(@viewing_file && Path.basename(@viewing_file)) || ""}
            </span>
            <div class="flex items-center gap-2">
              <button
                :if={@viewing_file && !@editing}
                phx-click="edit_file"
                class="btn btn-ghost btn-sm gap-1"
              >
                <span class="hero-pencil-square size-4"></span> Edit
              </button>
              <.link
                :if={@viewing_file}
                href={
                  ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/files/download/#{@viewing_file || ""}"
                }
                class="btn btn-ghost btn-sm gap-1"
              >
                <span class="hero-arrow-down-tray size-4"></span> Download
              </.link>
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click={JS.push("close_viewer") |> hide_confirm("#file-viewer-modal")}
              >
                <span class="hero-x-mark size-4"></span>
              </button>
            </div>
          </div>

          <%!-- Read-only view --%>
          <pre
            :if={!@editing}
            class="p-4 bg-base-200 rounded-lg overflow-x-auto text-sm font-mono whitespace-pre-wrap flex-1 overflow-y-auto"
          >{@file_content || ""}</pre>

          <%!-- Editor --%>
          <form :if={@editing} phx-submit="save_file" class="flex flex-col flex-1 gap-2">
            <textarea
              name="content"
              class="textarea textarea-bordered w-full font-mono text-sm flex-1 min-h-[50vh]"
              spellcheck="false"
            >{@file_content}</textarea>
            <div class="flex items-center gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Save</button>
              <button
                type="button"
                phx-click={JS.push("close_viewer") |> hide_confirm("#file-viewer-modal")}
                class="btn btn-ghost btn-sm"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
        <div
          class="modal-backdrop"
          phx-click={JS.push("close_viewer") |> hide_confirm("#file-viewer-modal")}
        >
        </div>
      </div>
    </div>
    """
  end

  defp entry_path("", name), do: name
  defp entry_path(current, name), do: Path.join(current, name)
end
