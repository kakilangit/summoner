defmodule SummonerWeb.GalleryLive.Index do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Phoenix.LiveView.JS
  alias Summoner.Media

  @max_gallery_items 100

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Spellbook Gallery - #{workspace.name}",
        filter_type: nil,
        filter_source: nil,
        filter_status: nil,
        selected: MapSet.new()
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Gallery", nil}
        ]
      )
      |> load_attachments()
      |> load_quota()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    socket =
      socket
      |> assign(
        filter_type: blank_to_nil(params["type"]),
        filter_source: blank_to_nil(params["source"]),
        filter_status: blank_to_nil(params["status"]),
        selected: MapSet.new()
      )
      |> load_attachments()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected, id) do
        MapSet.delete(socket.assigns.selected, id)
      else
        MapSet.put(socket.assigns.selected, id)
      end

    {:noreply, assign(socket, selected: selected)}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    all_ids = Enum.map(socket.assigns.attachments, & &1.id)
    {:noreply, assign(socket, selected: MapSet.new(all_ids))}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, selected: MapSet.new())}
  end

  @impl true
  def handle_event("bulk_delete", _params, socket) do
    authorize(socket, :configure, fn -> do_bulk_delete(socket) end)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    authorize(socket, :configure, fn -> do_delete(socket, id) end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Spellbook Gallery</h1>
        <div class="flex items-center gap-2">
          <.quota_badge used={@storage_used} max={@storage_max} />
        </div>
      </div>

      <form phx-change="filter" class="flex flex-wrap gap-3 items-end">
        <label class="form-control w-auto">
          <span class="label-text text-xs">Type</span>
          <select name="type" class="select select-sm select-bordered">
            <option value="">All</option>
            <option value="image" selected={@filter_type == "image"}>Image</option>
            <option value="video" selected={@filter_type == "video"}>Video</option>
          </select>
        </label>
        <label class="form-control w-auto">
          <span class="label-text text-xs">Source</span>
          <select name="source" class="select select-sm select-bordered">
            <option value="">All</option>
            <option value="generated" selected={@filter_source == "generated"}>Forged</option>
            <option value="uploaded" selected={@filter_source == "uploaded"}>Offered</option>
          </select>
        </label>
        <label class="form-control w-auto">
          <span class="label-text text-xs">Status</span>
          <select name="status" class="select select-sm select-bordered">
            <option value="">All</option>
            <option value="ready" selected={@filter_status == "ready"}>Ready</option>
            <option value="pending" selected={@filter_status == "pending"}>Standing By</option>
            <option value="failed" selected={@filter_status == "failed"}>Failed</option>
          </select>
        </label>
      </form>

      <div :if={@can?.(:configure) and MapSet.size(@selected) > 0} class="flex items-center gap-3">
        <span class="text-sm text-base-content/60">
          {MapSet.size(@selected)} selected
        </span>
        <button phx-click="deselect_all" class="btn btn-ghost btn-xs">Deselect All</button>
        <button
          phx-click={show_confirm("#bulk-delete-confirm")}
          class="btn btn-error btn-xs btn-outline"
        >
          Delete Selected
        </button>
        <.confirm_modal
          id="bulk-delete-confirm"
          title="Delete selected media?"
          message={"Permanently delete #{MapSet.size(@selected)} item(s). This cannot be undone."}
          confirm_text="Delete"
          on_confirm={JS.push("bulk_delete")}
        />
      </div>

      <div :if={@attachments == []} class="text-center py-12 text-base-content/60">
        <span class="hero-photo size-12 mx-auto mb-3 block opacity-40"></span>
        <p>No artifacts yet.</p>
      </div>

      <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">
        <.gallery_card
          :for={attachment <- @attachments}
          attachment={attachment}
          workspace={@workspace}
          selected={MapSet.member?(@selected, attachment.id)}
          can_configure={@can?.(:configure)}
        />
      </div>
    </div>
    """
  end

  attr :attachment, :map, required: true
  attr :workspace, :map, required: true
  attr :selected, :boolean, default: false
  attr :can_configure, :boolean, default: false

  defp gallery_card(assigns) do
    ~H"""
    <div class={[
      "relative group rounded-lg overflow-hidden border",
      if(@selected, do: "border-primary border-2", else: "border-base-300")
    ]}>
      <div
        :if={@can_configure}
        class="absolute top-2 left-2 z-10"
        phx-click="toggle_select"
        phx-value-id={@attachment.id}
      >
        <input
          type="checkbox"
          class="checkbox checkbox-sm checkbox-primary"
          checked={@selected}
          readonly
        />
      </div>

      <div :if={@attachment.status == :ready and @attachment.type == :image} class="aspect-square">
        <img
          src={Media.media_url(@attachment)}
          alt={@attachment.prompt || "Image"}
          class="w-full h-full object-cover"
          loading="lazy"
        />
      </div>

      <div
        :if={@attachment.status == :ready and @attachment.type == :video}
        class="aspect-square bg-base-200 flex items-center justify-center"
      >
        <video class="w-full h-full object-cover" preload="metadata" muted>
          <source src={Media.media_url(@attachment)} type={@attachment.content_type} />
        </video>
      </div>

      <div
        :if={@attachment.status == :pending}
        class="aspect-square bg-base-200 flex items-center justify-center animate-pulse"
      >
        <span class="text-xs text-base-content/40">Standing By...</span>
      </div>

      <div
        :if={@attachment.status == :failed}
        class="aspect-square bg-error/10 flex flex-col items-center justify-center gap-1"
      >
        <span class="hero-x-circle size-6 text-error"></span>
        <span class="text-xs text-error">Failed</span>
      </div>

      <div class="p-2 bg-base-100 space-y-1">
        <div class="flex items-center gap-1">
          <span class={[
            "badge badge-xs",
            status_badge_class(@attachment.status)
          ]}>
            {status_label(@attachment.status)}
          </span>
          <span class="badge badge-xs badge-outline">
            {source_label(@attachment.source)}
          </span>
          <span :if={@attachment.type == :video} class="badge badge-xs badge-outline">
            Video
          </span>
        </div>
        <p
          :if={@attachment.prompt}
          class="text-xs text-base-content/60 truncate"
          title={@attachment.prompt}
        >
          {@attachment.prompt}
        </p>
        <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
          <a
            :if={@attachment.status == :ready}
            href={Media.media_url(@attachment)}
            download={@attachment.filename}
            class="btn btn-ghost btn-xs"
            title="Download"
          >
            <span class="hero-arrow-down-tray size-3.5"></span>
          </a>
          <button
            :if={@can_configure}
            phx-click={show_confirm("#delete-media-#{@attachment.id}")}
            class="btn btn-ghost btn-xs text-error"
            title="Delete"
          >
            <span class="hero-trash size-3.5"></span>
          </button>
          <.confirm_modal
            :if={@can_configure}
            id={"delete-media-#{@attachment.id}"}
            title="Delete this artifact?"
            message="The file will be permanently removed."
            confirm_text="Delete"
            on_confirm={JS.push("delete", value: %{id: @attachment.id})}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :used, :integer, required: true
  attr :max, :integer, required: true

  defp quota_badge(assigns) do
    pct = if assigns.max > 0, do: round(assigns.used / assigns.max * 100), else: 0
    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div class="flex items-center gap-2 text-xs text-base-content/60">
      <span>{format_bytes(@used)} / {format_bytes(@max)}</span>
      <progress
        class={[
          "progress w-20",
          cond do
            @pct >= 90 -> "progress-error"
            @pct >= 70 -> "progress-warning"
            true -> "progress-primary"
          end
        ]}
        value={@pct}
        max="100"
      >
      </progress>
    </div>
    """
  end

  defp load_attachments(socket) do
    workspace_id = socket.assigns.workspace.id

    opts =
      [limit: @max_gallery_items]
      |> maybe_add_filter(:type, socket.assigns.filter_type)
      |> maybe_add_filter(:source, socket.assigns.filter_source)
      |> maybe_add_filter(:status, socket.assigns.filter_status)

    assign(socket, attachments: Media.list_workspace_attachments(workspace_id, opts))
  end

  defp load_quota(socket) do
    workspace_id = socket.assigns.workspace.id

    assign(socket,
      storage_used: Media.workspace_storage_used(workspace_id),
      storage_max: Media.max_workspace_storage()
    )
  end

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, key, value), do: Keyword.put(opts, key, coerce_filter(key, value))

  defp coerce_filter(:type, v), do: String.to_existing_atom(v)
  defp coerce_filter(:source, v), do: String.to_existing_atom(v)
  defp coerce_filter(:status, v), do: String.to_existing_atom(v)
  defp coerce_filter(_key, v), do: v

  defp do_bulk_delete(socket) do
    ids = MapSet.to_list(socket.assigns.selected)

    Enum.each(ids, fn id ->
      case Media.get_attachment(id) do
        nil -> :ok
        attachment -> Media.delete_attachment(attachment)
      end
    end)

    socket =
      socket
      |> assign(selected: MapSet.new())
      |> load_attachments()
      |> load_quota()
      |> put_flash(:info, "Deleted #{length(ids)} artifact(s).")

    {:noreply, socket}
  end

  defp do_delete(socket, id) do
    case Media.get_attachment(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Artifact not found.")}

      attachment ->
        Media.delete_attachment(attachment)

        socket =
          socket
          |> assign(selected: MapSet.delete(socket.assigns.selected, id))
          |> load_attachments()
          |> load_quota()
          |> put_flash(:info, "Artifact deleted.")

        {:noreply, socket}
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp status_label(:pending), do: "Standing By"
  defp status_label(:ready), do: "Ready"
  defp status_label(:failed), do: "Failed"

  defp source_label(:generated), do: "Forged"
  defp source_label(:uploaded), do: "Uploaded"

  defp status_badge_class(:pending), do: "badge-warning"
  defp status_badge_class(:ready), do: "badge-success"
  defp status_badge_class(:failed), do: "badge-error"

  defp format_bytes(bytes) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 1)} GB"
  end

  defp format_bytes(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end

  defp format_bytes(bytes) when bytes >= 1_024 do
    "#{Float.round(bytes / 1_024, 1)} KB"
  end

  defp format_bytes(bytes), do: "#{bytes} B"
end
