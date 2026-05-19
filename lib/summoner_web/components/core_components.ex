defmodule SummonerWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: SummonerWeb.Gettext

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      phx-hook="AutoDismiss"
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  @doc """
  Renders a text editor with a compact preview and a full-screen modal editor.

  The preview shows a truncated view of the content with an "Edit" button.
  Clicking it opens a modal with a large monospace textarea for comfortable editing.

  ## Example

      <.text_editor field={@form[:system_prompt]} label="Instructions" />

  Can also be used without a form field:

      <.text_editor id="my-editor" name="instruction" value={@instruction} label="Instructions" />
  """
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :id, :string, default: nil
  attr :name, :string, default: nil
  attr :value, :string, default: nil
  attr :label, :string, default: nil
  attr :placeholder, :string, default: ""
  attr :rows, :integer, default: 20

  def text_editor(assigns) do
    assigns =
      if assigns.field do
        assigns
        |> assign(:id, assigns.id || assigns.field.id)
        |> assign(:name, assigns.name || assigns.field.name)
        |> assign(:value, Form.normalize_value("textarea", assigns.field.value))
        |> assign_new(:errors, fn ->
          Enum.map(assigns.field.errors, &translate_error/1)
        end)
      else
        assign_new(assigns, :errors, fn -> [] end)
      end

    ~H"""
    <div class="fieldset mb-2">
      <span :if={@label} class="label mb-1">{@label}</span>
      <div class="relative">
        <div
          id={"text-editor-preview-#{@id}"}
          class="w-full min-h-[3rem] flex items-start rounded-lg border border-base-300 bg-base-200/30 px-3 py-2 text-xs font-mono whitespace-pre-line text-base-content/60 cursor-pointer hover:border-primary/40 transition-colors"
          phx-click={show_confirm("#text-editor-modal-#{@id}")}
        >
          <span
            data-placeholder
            class="text-base-content/30 italic"
            style={if @value != "" and not is_nil(@value), do: "display:none"}
          >
            {@placeholder}
          </span>
          <span
            data-content
            style={if @value == "" or is_nil(@value), do: "display:none"}
          >
            {@value}
          </span>
        </div>
        <button
          type="button"
          class="absolute top-2 right-2 btn btn-ghost btn-xs"
          phx-click={show_confirm("#text-editor-modal-#{@id}")}
        >
          <span class="hero-pencil-square size-4"></span>
        </button>
      </div>
      <textarea id={@id} name={@name} class="hidden" phx-hook="TextEditorTarget">{@value}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>

      <div id={"text-editor-modal-#{@id}"} class="modal modal-middle" role="dialog">
        <div class="modal-box max-w-2xl flex flex-col p-5">
          <div class="flex items-center justify-between mb-2">
            <h3 class="font-semibold text-base">{@label || "Edit"}</h3>
            <button
              type="button"
              class="btn btn-ghost btn-xs btn-circle"
              phx-click={hide_confirm("#text-editor-modal-#{@id}")}
            >
              <span class="hero-x-mark size-4"></span>
            </button>
          </div>
          <textarea
            id={"text-editor-textarea-#{@id}"}
            class="w-full max-h-[50vh] bg-base-200/50 border border-base-300 rounded-lg p-3 font-mono text-sm leading-6 resize-y focus:outline-none focus:border-primary/50 focus:ring-1 focus:ring-primary/20 placeholder:text-base-content/30"
            rows={@rows}
            placeholder={@placeholder}
            phx-hook="TextEditorModal"
            data-target={@id}
          >{@value}</textarea>
          <div class="modal-action mt-2">
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click={hide_confirm("#text-editor-modal-#{@id}")}
            >
              Cancel
            </button>
            <button
              type="button"
              class="btn btn-primary btn-sm"
              id={"text-editor-apply-#{@id}"}
              phx-hook="TextEditorApply"
              data-target={@id}
              phx-click={hide_confirm("#text-editor-modal-#{@id}")}
            >
              Apply
            </button>
          </div>
        </div>
        <div class="modal-backdrop" phx-click={hide_confirm("#text-editor-modal-#{@id}")}></div>
      </div>
    </div>
    """
  end

  @doc """
  Shows a confirm modal dialog.

  Returns a `Phoenix.LiveView.JS` command that opens the modal
  identified by the given `id`.

  ## Example

      <button phx-click={show_confirm("#delete-modal-123")}>Delete</.button>
  """
  def show_confirm(js \\ %JS{}, id) do
    js
    |> JS.add_class("modal-open", to: id)
  end

  @doc """
  Hides a confirm modal dialog.
  """
  def hide_confirm(js \\ %JS{}, id) do
    js
    |> JS.remove_class("modal-open", to: id)
  end

  @doc """
  Renders a confirm modal dialog using DaisyUI.

  The trigger button should call `show_confirm/2` to open the modal.
  On confirm, the modal fires the `on_confirm` JS command (typically
  a `phx-click` push) and auto-closes.

  ## Assigns

    * `id` (required) — unique DOM id for the modal
    * `title` — modal heading (default: "Are you sure?")
    * `message` — body text explaining what will happen
    * `confirm_text` — confirm button label (default: "Confirm")
    * `cancel_text` — cancel button label (default: "Cancel")
    * `variant` — confirm button style: "error" or "warning" (default: "error")
    * `on_confirm` — `Phoenix.LiveView.JS` command to run on confirm

  ## Example

      <button phx-click={show_confirm("#delete-item-123")}>
        Delete
      </button>

      <.confirm_modal
        id="delete-item-123"
        title="Delete item?"
        message="This action cannot be undone."
        on_confirm={JS.push("delete", value: %{id: item.id})}
      />
  """
  attr :id, :string, required: true
  attr :title, :string, default: "Are you sure?"
  attr :message, :string, default: "This action cannot be undone."
  attr :confirm_text, :string, default: "Confirm"
  attr :cancel_text, :string, default: "Cancel"
  attr :variant, :string, values: ~w(error warning), default: "error"
  attr :on_confirm, JS, required: true

  def confirm_modal(assigns) do
    ~H"""
    <div id={@id} class="modal" role="dialog">
      <div class="modal-box">
        <h3 class="text-lg font-bold">{@title}</h3>
        <p class="py-4 text-base-content/70">{@message}</p>
        <div class="modal-action">
          <button
            type="button"
            class="btn btn-ghost btn-sm"
            phx-click={hide_confirm("##{@id}")}
          >
            {@cancel_text}
          </button>
          <button
            type="button"
            class={[
              "btn btn-sm",
              @variant == "error" && "btn-error",
              @variant == "warning" && "btn-warning"
            ]}
            phx-click={@on_confirm |> hide_confirm("##{@id}")}
          >
            {@confirm_text}
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click={hide_confirm("##{@id}")}></div>
    </div>
    """
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(SummonerWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(SummonerWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  # -------------------------------------------------------------------
  # List Controls (search + sort)
  # -------------------------------------------------------------------

  @doc """
  Renders list controls: a search input and a sort dropdown.

  Emits `"filter"` with `%{"filter" => value}` on search input change,
  and `"sort"` with `%{"field" => field}` on sort option click.
  The sort direction toggles when clicking the already-active sort field.

  ## Attributes

    * `:filter` — current filter string (default `""`)
    * `:sort_by` — current sort field atom (required)
    * `:sort_dir` — `:asc` or `:desc` (required)
    * `:sort_options` — list of `{label, field_atom}` tuples (required)
    * `:placeholder` — search placeholder text (default `"Search..."`)

  ## Examples

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={[{"Name", :name}, {"Created", :inserted_at}]}
      />
  """
  attr :filter, :string, default: ""
  attr :sort_by, :atom, required: true
  attr :sort_dir, :atom, required: true
  attr :sort_options, :list, required: true, doc: "list of {label, field_atom} tuples"
  attr :placeholder, :string, default: "Search..."

  def list_controls(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row gap-3">
      <form phx-change="filter" phx-submit="filter" class="flex-1">
        <input
          type="text"
          value={@filter}
          placeholder={@placeholder}
          phx-debounce="300"
          name="filter"
          class="input input-sm input-bordered w-full"
        />
      </form>
      <div class="dropdown dropdown-end">
        <div tabindex="0" role="button" class="btn btn-sm btn-ghost gap-1">
          <span class="hero-arrows-up-down size-4"></span>
          {sort_label(@sort_options, @sort_by)}
          <span :if={@sort_dir == :asc} class="hero-chevron-up size-3"></span>
          <span :if={@sort_dir == :desc} class="hero-chevron-down size-3"></span>
        </div>
        <ul
          tabindex="0"
          class="dropdown-content z-10 menu menu-sm p-2 shadow bg-base-200 rounded-box w-48"
        >
          <li :for={{label, field} <- @sort_options}>
            <button
              phx-click="sort"
              phx-value-field={field}
              class={[@sort_by == field && "active"]}
            >
              {label}
              <span :if={@sort_by == field && @sort_dir == :asc} class="hero-chevron-up size-3">
              </span>
              <span :if={@sort_by == field && @sort_dir == :desc} class="hero-chevron-down size-3">
              </span>
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp sort_label(options, sort_by) do
    case List.keyfind(options, sort_by, 1) do
      {label, _} -> label
      nil -> "Sort"
    end
  end

  # -------------------------------------------------------------------
  # Pagination
  # -------------------------------------------------------------------

  @doc """
  Renders pagination controls.

  Expects a `%Summoner.Pagination{}` struct. Emits a `"paginate"`
  event with `%{"page" => page_number}` when a page button is clicked.

  ## Examples

      <.pagination page={@page} />
  """
  attr :page, :any, required: true, doc: "a %Summoner.Pagination{} struct"
  attr :event, :string, default: "paginate", doc: "the event name to emit"

  def pagination(assigns) do
    ~H"""
    <div :if={@page.total_pages > 1} class="flex items-center justify-between mt-4">
      <div class="text-sm text-base-content/60">
        Showing {(@page.page - 1) * @page.per_page + 1}–{min(
          @page.page * @page.per_page,
          @page.total_entries
        )} of {@page.total_entries}
      </div>
      <div class="join">
        <button
          :if={@page.page > 1}
          phx-click={@event}
          phx-value-page={@page.page - 1}
          class="join-item btn btn-sm"
        >
          <span class="hero-chevron-left size-4"></span>
        </button>
        <button
          :for={pg <- page_range(@page.page, @page.total_pages)}
          phx-click={@event}
          phx-value-page={pg}
          class={["join-item btn btn-sm", pg == @page.page && "btn-active"]}
        >
          {pg}
        </button>
        <button
          :if={@page.page < @page.total_pages}
          phx-click={@event}
          phx-value-page={@page.page + 1}
          class="join-item btn btn-sm"
        >
          <span class="hero-chevron-right size-4"></span>
        </button>
      </div>
    </div>
    """
  end

  # Show at most 5 page buttons centered around the current page
  defp page_range(_current, total) when total <= 5, do: Enum.to_list(1..total)

  defp page_range(current, total) do
    start = max(1, current - 2)
    stop = min(total, start + 4)
    start = max(1, stop - 4)
    Enum.to_list(start..stop)
  end

  @doc """
  Renders an inline model (spirit) switcher dropdown for an agent.

  Shows the current model as a compact badge with a dropdown to switch.
  Sends a `"change_model"` event with `agent_id` and `model` values.

  ## Attributes

    * `:agent` - The agent struct (must have `:provider` preloaded). Required.
    * `:id` - Unique DOM id. Required.

  ## Examples

      <.model_switcher agent={@agent} id="chat-model-switcher" />
  """
  attr :agent, :map, required: true
  attr :id, :string, required: true

  def model_switcher(assigns) do
    local = assigns.agent.local_agent
    models = cached_models(local)
    provider_name = provider_display_name(local)
    current_model = local && local.model

    assigns =
      assign(assigns, models: models, provider_name: provider_name, current_model: current_model)

    ~H"""
    <div id={@id} class="dropdown">
      <div
        tabindex="0"
        role="button"
        class={[
          "inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs",
          "border border-base-content/10 bg-base-100/80",
          "cursor-pointer select-none",
          "hover:border-primary/40 hover:bg-primary/5",
          "active:scale-95 transition-all duration-150"
        ]}
        title={"Current spirit: #{@current_model}\nGateway: #{@provider_name}"}
      >
        <span class="hero-cpu-chip size-3 text-base-content/40"></span>
        <span class="max-w-36 truncate font-medium text-base-content/70">
          {short_model_name(@current_model)}
        </span>
        <span class="hero-chevron-up-down size-3 text-base-content/30"></span>
      </div>
      <div
        tabindex="0"
        class={[
          "dropdown-content z-50 mt-2",
          "w-80 rounded-xl border border-base-300 bg-base-100 shadow-xl",
          "overflow-hidden"
        ]}
      >
        <div class="px-3 py-2 border-b border-base-200 bg-base-200/50">
          <p class="text-xs font-semibold text-base-content/60 uppercase tracking-wider">
            Switch Spirit
          </p>
          <p :if={@provider_name} class="text-xs text-base-content/40 mt-0.5">
            via {@provider_name}
          </p>
        </div>
        <ul class="menu menu-sm max-h-56 overflow-y-auto p-1.5 flex-nowrap">
          <li :if={@models == []}>
            <span class="text-xs text-base-content/40 italic py-3 justify-center">
              No cached spirits — refresh the gateway
            </span>
          </li>
          <li :for={model <- @models}>
            <button
              phx-click="change_model"
              phx-value-agent_id={@agent.id}
              phx-value-model={model}
              class={[
                "flex items-center gap-2 rounded-lg text-xs",
                if(model == @current_model,
                  do: "bg-primary/10 text-primary font-medium",
                  else: "hover:bg-base-200"
                )
              ]}
            >
              <span class={[
                "size-1.5 rounded-full flex-shrink-0",
                if(model == @current_model, do: "bg-primary", else: "bg-base-content/20")
              ]} />
              <span class="truncate flex-1">{short_model_name(model)}</span>
              <span
                :if={model == @current_model}
                class="hero-check-circle-solid size-4 text-primary flex-shrink-0"
              />
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp cached_models(%{provider: %{cached_models: models}}) when is_list(models), do: models
  defp cached_models(_), do: []

  defp provider_display_name(%{provider: %{name: name}}) when is_binary(name), do: name
  defp provider_display_name(_), do: nil

  @doc """
  Returns the short display name for a model string (last segment after `/`).
  """
  def short_model_name(model) when is_binary(model) do
    model |> String.split("/") |> List.last()
  end

  def short_model_name(_), do: "unknown"
end
