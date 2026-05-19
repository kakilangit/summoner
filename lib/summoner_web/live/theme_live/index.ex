defmodule SummonerWeb.ThemeLive.Index do
  use SummonerWeb, :live_view

  alias Summoner.Adapters.Persistence.Accounts
  alias Summoner.Adapters.Persistence.Themes

  @max_upload_size 1_048_576

  @impl true
  def mount(_params, _session, socket) do
    themes = Themes.list_themes()
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(
        page_title: "Themes",
        themes: themes,
        active_theme: user.theme
      )
      |> allow_upload(:theme_zip,
        accept: ~w(.zip),
        max_entries: 1,
        max_file_size: @max_upload_size
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("activate", %{"name" => name}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_theme(user, name) do
      {:ok, _user} ->
        # Full redirect required — root layout sets data-theme on <html>
        {:noreply, redirect(socket, to: ~p"/themes")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to set theme.")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    theme = Themes.get_theme!(id)

    case Themes.delete_theme(theme) do
      {:ok, _theme} ->
        Themes.write_css_file()
        {:noreply, assign(socket, themes: Themes.list_themes())}

      {:error, :builtin_theme} ->
        {:noreply, put_flash(socket, :error, "Built-in themes cannot be deleted.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete theme.")}
    end
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("install_theme", _params, socket) do
    consumed =
      consume_uploaded_entries(socket, :theme_zip, fn %{path: path}, _entry ->
        zip_binary = File.read!(path)

        case Themes.import_from_zip(zip_binary) do
          {:ok, theme} ->
            Themes.write_css_file()
            {:ok, {:ok, theme}}

          {:error, reason} ->
            {:ok, {:error, reason}}
        end
      end)

    case consumed do
      [{:ok, _theme}] ->
        {:noreply,
         socket
         |> assign(themes: Themes.list_themes())
         |> put_flash(:info, "Theme installed successfully.")}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, import_error_message(reason))}

      [] ->
        {:noreply, socket}
    end
  end

  defp import_error_message(:theme_limit_reached), do: "Maximum of 50 themes reached."
  defp import_error_message(:zip_too_large), do: "Zip file exceeds 1 MB limit."
  defp import_error_message(:zip_too_many_entries), do: "Zip contains too many entries (max 5)."
  defp import_error_message(:missing_theme_json), do: "Zip must contain a theme.json file."
  defp import_error_message(:invalid_zip), do: "Invalid zip file."
  defp import_error_message(:invalid_json), do: "Invalid JSON in theme.json."
  defp import_error_message(:invalid_theme_json), do: "theme.json must be a JSON object."

  defp import_error_message(%Ecto.Changeset{} = changeset) do
    errors =
      changeset
      |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
      |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)

    "Invalid theme: #{errors}"
  end

  defp import_error_message(reason), do: "Failed to install: #{inspect(reason)}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Themes</h1>
      </div>

      <%!-- Upload section --%>
      <div class="card bg-base-200 p-4">
        <h2 class="text-sm font-medium mb-3">Install Theme</h2>
        <form phx-submit="install_theme" phx-change="validate_upload" class="flex items-end gap-3">
          <div class="flex-1">
            <.live_file_input
              upload={@uploads.theme_zip}
              class="file-input file-input-bordered file-input-sm w-full"
            />
            <p :for={err <- upload_errors(@uploads.theme_zip)} class="text-error text-xs mt-1">
              {upload_error_to_string(err)}
            </p>
          </div>
          <button
            type="submit"
            class="btn btn-primary btn-sm"
            disabled={@uploads.theme_zip.entries == []}
          >
            Install
          </button>
        </form>
        <p class="text-xs text-base-content/50 mt-2">
          Upload a .zip file containing a theme.json with DaisyUI color tokens.
        </p>
      </div>

      <%!-- Theme grid --%>
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <div
          :for={theme <- @themes}
          class={[
            "card bg-base-200 shadow-sm",
            theme.name == @active_theme && "ring-2 ring-primary"
          ]}
        >
          <div class="card-body p-4">
            <div class="flex items-center justify-between">
              <div>
                <h3 class="font-medium">{theme.display_name}</h3>
                <p class="text-xs text-base-content/50">
                  {theme.color_scheme}
                  <span :if={theme.author}>{" · #{theme.author}"}</span>
                  <span :if={theme.version}>{" · v#{theme.version}"}</span>
                </p>
              </div>
              <span :if={theme.is_builtin} class="badge badge-ghost badge-xs">built-in</span>
            </div>

            <%!-- Color swatch preview --%>
            <.theme_swatches tokens={theme.tokens} />

            <div class="card-actions justify-end mt-2">
              <button
                :if={theme.name != @active_theme}
                phx-click="activate"
                phx-value-name={theme.name}
                class="btn btn-sm btn-primary"
              >
                Activate
              </button>
              <span :if={theme.name == @active_theme} class="badge badge-primary badge-sm">
                Active
              </span>
              <button
                :if={!theme.is_builtin}
                phx-click="delete"
                phx-value-id={theme.id}
                data-confirm="Delete this theme?"
                class="btn btn-sm btn-ghost btn-error"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Components
  # -------------------------------------------------------------------

  attr :tokens, :map, required: true

  defp theme_swatches(assigns) do
    color_keys = ~w(
      color-base-100 color-base-200 color-base-300
      color-primary color-secondary color-accent
      color-info color-success color-warning color-error
    )

    swatches =
      Enum.map(color_keys, fn key ->
        %{name: key, value: Map.get(assigns.tokens, key, "oklch(50% 0 0)")}
      end)

    assigns = assign(assigns, swatches: swatches)

    ~H"""
    <div class="flex gap-1 mt-2">
      <div
        :for={swatch <- @swatches}
        class="w-5 h-5 rounded-sm border border-base-300"
        style={"background: #{swatch.value}"}
        title={swatch.name}
      />
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 1 MB)."
  defp upload_error_to_string(:not_accepted), do: "Only .zip files are accepted."
  defp upload_error_to_string(:too_many_files), do: "Only one file at a time."
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
