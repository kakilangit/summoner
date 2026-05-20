defmodule SummonerWeb.ConversationComponents do
  @moduledoc """
  Shared HEEx function components for channel (conversation) views.

  Both ConversationLive.Show and SwarmLive.Session render the same escalation alerts,
  message lists, message bubbles, inline errors, streaming indicators,
  subtask panels, thought streams, and message input forms. This module
  extracts those into reusable components.
  """
  use Phoenix.Component

  alias Summoner.Ports.Persistence.Media
  alias Summoner.Domain.Types.Content

  # -------------------------------------------------------------------
  # Content block rendering
  # -------------------------------------------------------------------

  attr :blocks, :list, default: []

  def content_blocks(assigns) do
    ~H"""
    <div :for={block <- @blocks || []}>
      <div :if={block["type"] == "text"}>
        {markdown(block["text"])}
      </div>
      <.media_image :if={block["type"] == "image"} block={block} />
      <.media_video_placeholder :if={block["type"] == "video"} block={block} />
    </div>
    """
  end

  attr :block, :map, required: true

  defp media_image(assigns) do
    attachment = resolve_attachment(assigns.block)
    assigns = assign(assigns, :attachment, attachment)

    ~H"""
    <div :if={@attachment && @attachment.status == :ready} class="my-2">
      <img
        src={Summoner.Ports.Persistence.Media.media_url(@attachment)}
        alt={@block["alt"] || "Image"}
        class="rounded-lg max-w-sm max-h-80 cursor-pointer hover:opacity-90 transition-opacity border border-base-300"
        loading="lazy"
        phx-click={Phoenix.LiveView.JS.toggle(to: "#lightbox-#{@attachment.id}")}
      />
      <div class="flex items-center gap-1 mt-1">
        <a
          href={Summoner.Ports.Persistence.Media.media_url(@attachment)}
          download={@attachment.filename}
          class="btn btn-ghost btn-xs"
          title="Download"
        >
          <span class="hero-arrow-down-tray size-3.5"></span>
        </a>
      </div>
      <%!-- Lightbox overlay --%>
      <div
        id={"lightbox-#{@attachment.id}"}
        class="hidden fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-4"
        phx-click={Phoenix.LiveView.JS.toggle(to: "#lightbox-#{@attachment.id}")}
      >
        <img
          src={Summoner.Ports.Persistence.Media.media_url(@attachment)}
          alt={@block["alt"] || "Image"}
          class="max-w-full max-h-full rounded-lg shadow-2xl"
        />
      </div>
    </div>
    <div
      :if={@attachment && @attachment.status == :pending}
      class="my-2 w-64 h-40 bg-base-200 rounded-lg animate-pulse flex items-center justify-center"
    >
      <span class="text-xs text-base-content/40">Standing By...</span>
    </div>
    <.media_failed_badge :if={@attachment && @attachment.status == :failed} attachment={@attachment} />
    """
  end

  attr :block, :map, required: true

  defp media_video_placeholder(assigns) do
    attachment = resolve_attachment(assigns.block)
    assigns = assign(assigns, :attachment, attachment)

    ~H"""
    <div :if={@attachment && @attachment.status == :ready} class="my-2">
      <video
        controls
        preload="metadata"
        class="rounded-lg max-w-sm max-h-80 border border-base-300"
      >
        <source
          src={Summoner.Ports.Persistence.Media.media_url(@attachment)}
          type={@attachment.content_type}
        /> Your browser does not support video playback.
      </video>
      <div class="flex items-center gap-1 mt-1">
        <p :if={@block["alt"]} class="text-xs text-base-content/50">{@block["alt"]}</p>
        <a
          href={Summoner.Ports.Persistence.Media.media_url(@attachment)}
          download={@attachment.filename}
          class="btn btn-ghost btn-xs"
          title="Download"
        >
          <span class="hero-arrow-down-tray size-3.5"></span>
        </a>
      </div>
    </div>
    <div
      :if={@attachment && @attachment.status == :pending}
      class="my-2 flex items-center gap-2 text-xs text-base-content/50 bg-base-200 rounded-lg px-3 py-2 w-fit animate-pulse"
    >
      <span class="hero-film size-4"></span>
      <span>{@block["alt"] || "Video"} — channeling...</span>
    </div>
    <.media_failed_badge :if={@attachment && @attachment.status == :failed} attachment={@attachment} />
    <div
      :if={is_nil(@attachment)}
      class="my-2 flex items-center gap-2 text-xs text-base-content/50 bg-base-200 rounded-lg px-3 py-2 w-fit"
    >
      <span class="hero-film size-4"></span>
      <span>{@block["alt"] || "Video"}</span>
    </div>
    """
  end

  attr :attachment, :map, required: true

  defp media_failed_badge(assigns) do
    ~H"""
    <div class="my-2 flex items-center gap-2 text-xs bg-error/10 text-error rounded-lg px-3 py-2 w-fit">
      <span class="hero-x-circle size-4"></span>
      <span>Failed: {@attachment.error || "generation failed"}</span>
      <button
        phx-click="retry_media_generation"
        phx-value-id={@attachment.id}
        class="btn btn-error btn-xs btn-outline"
      >
        Retry
      </button>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Escalation alert
  # -------------------------------------------------------------------

  attr :escalation, :map, default: nil

  def escalation_alert(assigns) do
    ~H"""
    <div :if={@escalation} class="alert alert-warning my-2 rounded-xl shadow-sm">
      <span class="hero-exclamation-triangle size-5"></span>
      <div class="flex-1">
        <div class="font-medium text-sm">Escalation</div>
        <div class="text-xs">{@escalation.reason}</div>
      </div>
      <button phx-click="dismiss_escalation" class="btn btn-ghost btn-xs">Dismiss</button>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Inline error
  # -------------------------------------------------------------------

  attr :last_error, :string, default: nil

  def inline_error(assigns) do
    ~H"""
    <div :if={@last_error} class="flex items-start gap-2 justify-start">
      <div class="flex-shrink-0">
        <div class="size-8 rounded-full bg-error/10 flex items-center justify-center">
          <span class="hero-exclamation-triangle size-4 text-error"></span>
        </div>
      </div>
      <div class="flex-1 min-w-0 rounded-2xl rounded-tl-sm px-3 py-2 bg-error/5 border border-error/20">
        <div class="text-xs font-medium text-error mb-1">Error</div>
        <div class="text-sm text-error/80 break-words">{@last_error}</div>
        <div class="mt-1">
          <button phx-click="dismiss_error" class="btn btn-ghost btn-xs text-error/60">
            Dismiss
          </button>
        </div>
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Message (single message row with delete/restore, edit, actions)
  # -------------------------------------------------------------------

  attr :msg, :map, required: true
  attr :editing_message_id, :string, default: nil
  attr :editing_message_content, :string, default: ""
  slot :avatar_assistant
  slot :agent_label

  def message_row(assigns) do
    ~H"""
    <div class="group">
      <%!-- Deleted message --%>
      <div :if={@msg.deleted_at} class="flex items-center gap-1.5 w-full">
        <div class="text-xs text-base-content/30 italic">message removed</div>
        <button
          phx-click="restore_message"
          phx-value-id={@msg.id}
          class="btn btn-ghost btn-xs btn-square opacity-30 hover:opacity-80 transition-opacity"
          title="Restore message"
        >
          <span class="hero-arrow-uturn-left size-3"></span>
        </button>
      </div>

      <%!-- Normal message --%>
      <div
        :if={!@msg.deleted_at}
        class={["flex items-start gap-2", @msg.role == :user && "justify-end"]}
      >
        <%!-- Avatar for assistant --%>
        <div :if={@msg.role == :assistant} class="flex-shrink-0">
          {render_slot(@avatar_assistant)}
        </div>

        <div class={message_bubble_class(@msg.role)} id={"msg-#{@msg.id}"} phx-hook="CopyMessage">
          <%!-- Agent label slot --%>
          <div :if={@msg.role == :assistant && @msg.agent_id}>
            {render_slot(@agent_label)}
          </div>

          <%!-- Edit mode --%>
          <form
            :if={@msg.role == :user && @editing_message_id == @msg.id}
            phx-submit="save_edit"
            class="space-y-2"
          >
            <textarea
              name="content"
              class="textarea textarea-bordered w-full text-sm leading-relaxed min-h-[6rem] resize-none"
              phx-hook="AutoResize"
              id={"edit-#{@msg.id}"}
            >{@editing_message_content}</textarea>
            <div class="flex gap-1 justify-end">
              <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-xs">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary btn-xs">
                Save & Resend
              </button>
            </div>
          </form>

          <%!-- Thinking/reasoning block --%>
          <details
            :if={@msg.role == :assistant && @msg.thinking && @msg.thinking != ""}
            class="collapse collapse-arrow bg-base-200/50 rounded-lg mb-2"
          >
            <summary class="collapse-title text-xs font-medium min-h-0 py-2 px-3">
              <span class="opacity-60">Thinking</span>
            </summary>
            <div class="collapse-content px-3 pb-2">
              <div class="prose prose-xs max-w-none break-words opacity-70">
                {markdown(@msg.thinking)}
              </div>
            </div>
          </details>

          <%!-- Display mode --%>
          <div
            :if={@editing_message_id != @msg.id}
            class="prose prose-sm max-w-none break-words chat-prose"
            data-raw={Content.text_only(@msg.content)}
          >
            <.content_blocks blocks={@msg.content} />
          </div>
          <div
            :if={@editing_message_id != @msg.id}
            class="flex items-center justify-between mt-1"
          >
            <div class="text-[10px] opacity-40 flex items-center gap-1">
              {Summoner.Services.TimeZone.format_chat_timestamp(@msg.inserted_at)}
              <span
                :if={@msg.kind == :generate_image}
                class={[
                  "tooltip cursor-default before:text-xs",
                  if(@msg.role == :user, do: "tooltip-left", else: "tooltip-right")
                ]}
                data-tip="Forge Image"
              >
                <span class="hero-photo size-3 inline-block"></span>
              </span>
              <span
                :if={@msg.kind == :generate_video}
                class={[
                  "tooltip cursor-default before:text-xs",
                  if(@msg.role == :user, do: "tooltip-left", else: "tooltip-right")
                ]}
                data-tip="Forge Vision"
              >
                <span class="hero-film size-3 inline-block"></span>
              </span>
              <span
                :if={@msg.role == :assistant && (@msg.provider_name || @msg.model_name)}
                class="tooltip tooltip-right cursor-default before:text-xs before:font-medium before:bg-base-300 before:text-base-content before:max-w-none"
                data-tip={inference_tooltip(@msg.provider_name, @msg.model_name)}
              >
                <span class="hero-cpu-chip size-3 inline-block"></span>
              </span>
            </div>
            <div class="flex items-center gap-0.5">
              <button
                :if={@msg.role == :user}
                type="button"
                phx-click="edit_message"
                phx-value-id={@msg.id}
                class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-60 transition-opacity"
                title="Edit"
              >
                <span class="hero-pencil-square size-3"></span>
              </button>
              <button
                :if={@msg.role == :user}
                type="button"
                phx-click="resend_message"
                phx-value-id={@msg.id}
                class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-60 transition-opacity"
                title="Resend"
              >
                <span class="hero-arrow-path size-3"></span>
              </button>
              <button
                type="button"
                phx-click="delete_message"
                phx-value-id={@msg.id}
                class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-60 transition-opacity"
                title="Delete"
              >
                <span class="hero-trash size-3"></span>
              </button>
              <button
                type="button"
                data-copy="raw"
                class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-60 transition-opacity"
                title="Copy"
              >
                <span class="hero-clipboard-document size-3"></span>
              </button>
            </div>
          </div>
        </div>

        <%!-- Avatar for user --%>
        <div :if={@msg.role == :user} class="flex-shrink-0">
          <div class="size-8 rounded-full bg-primary flex items-center justify-center">
            <span class="hero-user size-4 text-primary-content"></span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Title editor
  # -------------------------------------------------------------------

  attr :conversation, :map, required: true
  attr :editing_title, :boolean, default: false
  attr :default_title, :string, default: "Channel"
  slot :extra_badges

  def title_editor(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <div :if={!@editing_title} class="flex items-center gap-2 min-w-0 flex-1">
        <h1
          class="text-lg font-bold truncate cursor-pointer hover:text-primary transition-colors"
          phx-click="edit_title"
        >
          {@conversation.title || @default_title}
        </h1>
        <button
          phx-click="edit_title"
          class="btn btn-ghost btn-xs opacity-40 hover:opacity-100 transition-opacity"
          title="Rename channel"
        >
          <span class="hero-pencil-square size-4"></span>
        </button>
        {render_slot(@extra_badges)}
      </div>
      <form
        :if={@editing_title}
        phx-submit="save_title"
        class="flex items-center gap-2 flex-1"
      >
        <input
          type="text"
          name="title"
          value={@conversation.title || ""}
          class="input input-bordered input-sm flex-1"
          autofocus
          phx-keydown="cancel_edit_title"
          phx-key="Escape"
        />
        <button type="submit" class="btn btn-primary btn-sm btn-square">
          <span class="hero-check size-4"></span>
        </button>
        <button
          type="button"
          phx-click="cancel_edit_title"
          class="btn btn-ghost btn-sm btn-square"
        >
          <span class="hero-x-mark size-4"></span>
        </button>
      </form>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Subtask panel
  # -------------------------------------------------------------------

  attr :subtasks, :list, default: []

  def subtask_panel(assigns) do
    ~H"""
    <div :if={@subtasks != []} class="flex-shrink-0 border-t border-base-300 py-2">
      <div class="collapse collapse-arrow bg-base-200/50 rounded-xl border border-base-300">
        <input type="checkbox" checked="checked" />
        <div class="collapse-title text-sm font-medium py-2 min-h-0">
          <span class="hero-list-bullet size-4 inline-block align-text-bottom mr-1"></span>
          Subtasks ({length(@subtasks)})
        </div>
        <div class="collapse-content !pb-3">
          <div class="space-y-1.5 text-sm max-h-40 overflow-y-auto">
            <div :for={subtask <- @subtasks} class="flex items-center gap-2 py-0.5">
              <span class={["badge badge-xs", subtask_status_class(subtask.status)]}>
                {subtask.status}
              </span>
              <span class="truncate text-base-content/80">{subtask.description}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Thought stream
  # -------------------------------------------------------------------

  attr :invocation_events, :list, default: []

  def thought_stream(assigns) do
    ~H"""
    <div :if={@invocation_events != []} class="flex-shrink-0 border-t border-base-300 py-2">
      <div class="collapse collapse-arrow bg-base-200/50 rounded-xl border border-base-300">
        <input type="checkbox" id="thought-stream-toggle" phx-update="ignore" />
        <div class="collapse-title text-sm font-medium py-2 min-h-0">
          <span class="hero-eye size-4 inline-block align-text-bottom mr-1"></span>
          Thought Stream ({length(@invocation_events)} events)
        </div>
        <div class="collapse-content !pb-3">
          <div class="space-y-1 text-xs font-mono max-h-32 overflow-y-auto">
            <div
              :for={event <- @invocation_events}
              class="text-base-content/60 py-0.5 border-l-2 border-base-300 pl-2"
            >
              {format_event(event)}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Message input
  # -------------------------------------------------------------------

  attr :message_input, :string, default: ""
  attr :processing, :boolean, default: false
  attr :placeholder, :string, default: "Message..."
  attr :uploads, :map, default: nil
  attr :media_mode, :atom, default: nil

  def message_input(assigns) do
    ~H"""
    <div class="flex-shrink-0 border-t border-base-300 px-1 py-3">
      <%!-- Upload previews --%>
      <div
        :if={@uploads && @uploads.images.entries != []}
        class="flex flex-wrap gap-2 mb-2 px-1"
      >
        <div
          :for={entry <- @uploads.images.entries}
          class="relative inline-block"
        >
          <.live_img_preview
            entry={entry}
            class="w-16 h-16 rounded-lg object-cover border border-base-300"
          />
          <button
            type="button"
            phx-click="cancel_upload"
            phx-value-ref={entry.ref}
            class="btn btn-xs btn-circle btn-error absolute -top-1.5 -right-1.5"
          >
            <span class="text-xs">&times;</span>
          </button>
          <div
            :for={err <- upload_errors(@uploads.images, entry)}
            class="text-error text-xs mt-0.5"
          >
            {upload_error_to_string(err)}
          </div>
        </div>
      </div>

      <form phx-submit="send_message" phx-change="validate_upload" class="flex items-center gap-2">
        <%!-- Upload button --%>
        <label
          :if={@uploads && !@processing}
          class="btn btn-ghost btn-square btn-sm cursor-pointer"
          title="Attach image"
        >
          <span class="hero-photo size-5"></span>
          <.live_file_input upload={@uploads.images} class="hidden" />
        </label>

        <%!-- Conjure mode toggle (cycles: off → image → video → off) --%>
        <button
          :if={!@processing}
          type="button"
          phx-click="toggle_media_mode"
          class={[
            "btn btn-square btn-sm",
            media_button_class(@media_mode)
          ]}
          title={media_button_title(@media_mode)}
        >
          <span class={media_button_icon(@media_mode)}></span>
        </button>

        <input
          type="text"
          name="message"
          id="message-input"
          placeholder={media_placeholder(@media_mode, @placeholder)}
          class={[
            "input input-bordered w-full flex-1",
            if(@media_mode, do: "focus:input-accent", else: "focus:input-primary")
          ]}
          autocomplete="off"
          autofocus
          phx-debounce="blur"
          phx-hook="MessageInput"
        />
        <button
          :if={!@processing}
          type="submit"
          class="btn btn-primary btn-square"
        >
          <span class="hero-paper-airplane size-5"></span>
        </button>
        <button
          :if={@processing}
          type="button"
          phx-click="cancel_invocation"
          class="btn btn-error btn-square"
          title="Cancel"
        >
          <span class="hero-stop size-5"></span>
        </button>
      </form>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  def message_bubble_class(:user) do
    "max-w-prose rounded-2xl rounded-tr-sm px-3 py-1.5 bg-primary text-primary-content"
  end

  def message_bubble_class(:assistant) do
    "rounded-2xl rounded-tl-sm px-3 py-1.5 bg-base-200 border border-base-300 flex-1 min-w-0"
  end

  def message_bubble_class(:system) do
    "max-w-prose rounded-2xl px-3 py-1.5 bg-warning/10 border border-warning/20 text-sm italic"
  end

  def message_bubble_class(:tool) do
    "max-w-prose rounded-2xl px-3 py-1.5 bg-base-300/50 border border-base-300 text-sm font-mono"
  end

  def message_bubble_class(_), do: message_bubble_class(:assistant)

  def subtask_status_class(:pending), do: "badge-ghost"
  def subtask_status_class(:claimed), do: "badge-info"
  def subtask_status_class(:running), do: "badge-warning"
  def subtask_status_class(:completed), do: "badge-success"
  def subtask_status_class(:failed), do: "badge-error"
  def subtask_status_class(:skipped), do: "badge-neutral"
  def subtask_status_class(_), do: "badge-ghost"

  def format_event(%{summary: summary}), do: summary
  def format_event(%{"summary" => summary}), do: summary
  def format_event(event), do: inspect(event)

  def markdown(nil), do: ""
  def markdown([]), do: ""

  def markdown(blocks) when is_list(blocks) do
    blocks
    |> Content.text_only()
    |> markdown()
  end

  def markdown(text) when is_binary(text) do
    html =
      text
      |> Earmark.as_html(escape: false, smartypants: false)
      |> case do
        {:ok, html, _messages} -> html
        {:error, html, _messages} -> html
      end

    Phoenix.HTML.raw(html)
  end

  defp inference_tooltip(provider_name, model_name) do
    [provider_name, model_name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp upload_error_to_string(:too_large), do: "Too large (max 10 MB)"
  defp upload_error_to_string(:not_accepted), do: "Invalid file type"
  defp upload_error_to_string(:too_many_files), do: "Max 4 images"
  defp upload_error_to_string(err), do: inspect(err)

  defp resolve_attachment(%{"media_attachment_id" => id}) when is_binary(id) do
    Media.get_attachment(id)
  end

  defp resolve_attachment(_block), do: nil

  defp media_button_class(nil), do: "btn-ghost"
  defp media_button_class(:image), do: "btn-accent"
  defp media_button_class(:video), do: "btn-secondary"

  defp media_button_title(nil), do: "Conjure mode (off)"
  defp media_button_title(:image), do: "Forge Image mode"
  defp media_button_title(:video), do: "Forge Vision mode"

  defp media_button_icon(nil), do: "hero-sparkles size-5"
  defp media_button_icon(:image), do: "hero-photo size-5"
  defp media_button_icon(:video), do: "hero-film size-5"

  defp media_placeholder(nil, default), do: default
  defp media_placeholder(:image, _default), do: "Describe the image to conjure..."
  defp media_placeholder(:video, _default), do: "Describe the vision to conjure..."
end
