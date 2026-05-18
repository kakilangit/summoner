defmodule SummonerWeb.WorkspaceLive.Settings do
  use SummonerWeb, :live_view

  alias Summoner.Media
  alias Summoner.Presets
  alias Summoner.Workspaces
  alias Summoner.Workspaces.Policy
  alias Summoner.Workspaces.Workspace

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    if Policy.can?(socket.assigns.membership, :manage_workspace) do
      ws_changeset = Workspace.changeset(workspace, %{})
      settings_changeset = Workspaces.WorkspaceSettings.changeset(workspace.settings, %{})

      socket =
        socket
        |> assign(page_title: "Settings - #{workspace.name}")
        |> assign(ws_form: to_form(ws_changeset, as: "workspace"))
        |> assign(form: to_form(settings_changeset))
        |> assign(delete_confirmation: "")
        |> assign(
          storage_used: Media.workspace_storage_used(workspace.id),
          storage_max: Media.max_workspace_storage(),
          pending_jobs: Media.pending_jobs_count(workspace.id)
        )
        |> assign(
          breadcrumbs: [
            {"Realms", ~p"/realms/#{workspace.tenant_id}/realms"},
            {workspace.name, ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}"},
            {"Settings", nil}
          ]
        )

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to do that.")
       |> redirect(to: ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}")}
    end
  end

  @impl true
  def handle_event("save_name", %{"workspace" => params}, socket) do
    case Workspaces.update_workspace(
           socket.assigns.current_scope,
           socket.assigns.workspace,
           params
         ) do
      {:ok, workspace} ->
        {:noreply,
         socket
         |> assign(workspace: workspace)
         |> assign(page_title: "Settings - #{workspace.name}")
         |> put_flash(:info, "Realm name updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, ws_form: to_form(changeset, as: "workspace"))}
    end
  end

  @impl true
  def handle_event("save", %{"workspace_settings" => params}, socket) do
    case Workspaces.update_settings(
           socket.assigns.current_scope,
           socket.assigns.workspace,
           params
         ) do
      {:ok, _settings} ->
        socket =
          socket
          |> put_flash(:info, "Settings updated successfully.")
          |> push_navigate(
            to:
              ~p"/realms/#{socket.assigns.workspace.tenant_id}/realms/#{socket.assigns.workspace.id}"
          )

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("reset_harness", _params, socket) do
    default = Presets.default_harness()
    settings = socket.assigns.workspace.settings
    changeset = Workspaces.WorkspaceSettings.changeset(settings, %{"harness" => default})
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("validate_delete", %{"confirmation" => name}, socket) do
    {:noreply, assign(socket, delete_confirmation: name)}
  end

  @impl true
  def handle_event("delete_workspace", _params, socket) do
    workspace = socket.assigns.workspace

    if socket.assigns.delete_confirmation == workspace.name do
      case Workspaces.delete_workspace(socket.assigns.current_scope, workspace) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Realm \"#{workspace.name}\" has been permanently deleted.")
           |> push_navigate(to: ~p"/guilds")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete sanctum.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Name does not match. Deletion cancelled.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-8">
      <h1 class="text-2xl font-bold">Realm Settings</h1>

      <section class="space-y-3">
        <h2 class="text-lg font-semibold border-b border-base-300 pb-2">General</h2>
        <.form
          for={@ws_form}
          id="workspace-name-form"
          phx-submit="save_name"
          class="space-y-4"
        >
          <.input field={@ws_form[:name]} type="text" label="Realm Name" required />
          <div>
            <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
              Rename
            </.button>
          </div>
        </.form>
      </section>

      <section class="space-y-3">
        <h2 class="text-lg font-semibold border-b border-base-300 pb-2">Inference</h2>
        <.form
          for={@form}
          id="settings-form"
          phx-submit="save"
          class="space-y-4"
        >
          <.input
            field={@form[:context_window_messages]}
            type="number"
            label="Context Window (messages)"
            min="1"
            required
          />
          <.input
            field={@form[:max_tool_output_chars]}
            type="number"
            label="Max Tool Output (characters)"
            min="1"
            required
          />
          <.input
            field={@form[:token_quota_monthly]}
            type="number"
            label="Monthly Token Quota"
            min="1"
            placeholder="Unlimited"
          />
          <.input
            field={@form[:budget_usd_monthly]}
            type="number"
            label="Monthly Budget (USD)"
            min="0.01"
            step="0.01"
            placeholder="Unlimited"
          />
          <div>
            <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
              Save Settings
            </.button>
          </div>
        </.form>
      </section>

      <section class="space-y-3">
        <h2 class="text-lg font-semibold border-b border-base-300 pb-2">Default Timeouts</h2>
        <p class="text-sm text-base-content/60">
          Default timeout values applied when creating new summons.
          Individual summons can override these values in their own settings.
        </p>
        <.form
          for={@form}
          id="timeouts-form"
          phx-submit="save"
          class="space-y-4"
        >
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input
              field={@form[:default_step_timeout_s]}
              type="number"
              label="Tool Timeout (seconds)"
              min="1"
              max="600"
              required
            />
            <.input
              field={@form[:default_total_timeout_s]}
              type="number"
              label="Invocation Timeout (seconds)"
              min="1"
              max="3600"
              required
            />
          </div>
          <p class="text-xs text-base-content/50">
            <strong>Tool Timeout</strong>
            — max time per tool call. <strong>Invocation Timeout</strong>
            — max total time for a summon's full response (also used as the per-turn timeout in partys).
          </p>
          <div>
            <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
              Save Timeouts
            </.button>
          </div>
        </.form>
      </section>

      <section class="space-y-3">
        <h2 class="text-lg font-semibold border-b border-base-300 pb-2">Harness</h2>
        <p class="text-sm text-base-content/60">
          Global operational guidelines prepended to every summon's system prompt in this sanctum.
        </p>
        <.form
          for={@form}
          id="harness-form"
          phx-submit="save"
          class="space-y-4"
        >
          <.text_editor
            field={@form[:harness]}
            label="Guidelines"
            placeholder="Enter operational guidelines for all summons..."
          />
          <div class="flex items-center gap-2">
            <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
              Save Harness
            </.button>
            <button
              type="button"
              phx-click="reset_harness"
              class="btn btn-ghost btn-sm"
            >
              Reset to Default
            </button>
          </div>
        </.form>
      </section>

      <section class="space-y-3">
        <h2 class="text-lg font-semibold border-b border-base-300 pb-2">Media Storage</h2>
        <div class="flex items-center gap-4">
          <div class="flex-1">
            <div class="flex justify-between text-sm mb-1">
              <span>{format_bytes(@storage_used)} used</span>
              <span>{format_bytes(@storage_max)} total</span>
            </div>
            <progress
              class={[
                "progress w-full",
                cond do
                  storage_pct(@storage_used, @storage_max) >= 90 -> "progress-error"
                  storage_pct(@storage_used, @storage_max) >= 70 -> "progress-warning"
                  true -> "progress-primary"
                end
              ]}
              value={storage_pct(@storage_used, @storage_max)}
              max="100"
            >
            </progress>
          </div>
        </div>
        <p class="text-xs text-base-content/60">
          {@pending_jobs} conjuration(s) currently channeling.
          <.link
            navigate={~p"/realms/#{@workspace.tenant_id}/realms/#{@workspace.id}/gallery"}
            class="link link-primary"
          >
            View Gallery
          </.link>
        </p>
      </section>

      <section class="space-y-3">
        <h2 class="text-lg font-semibold border-b border-error/30 pb-2 text-error">
          Danger Zone
        </h2>
        <div class="border border-error/30 rounded-lg p-4 space-y-3">
          <p class="text-sm">
            Permanently delete this sanctum and <strong>all</strong> its resources:
            summons, gateways, runes, channels, rituals, partys, seals, and grimoire entries.
            This action cannot be undone.
          </p>
          <form phx-change="validate_delete" phx-submit="delete_workspace" class="space-y-3">
            <label class="label">
              <span class="label-text">
                Type <strong>{@workspace.name}</strong> to confirm
              </span>
            </label>
            <input
              type="text"
              name="confirmation"
              value={@delete_confirmation}
              class="input input-bordered input-sm w-full"
              autocomplete="off"
            />
            <button
              type="submit"
              class="btn btn-error btn-sm"
              disabled={@delete_confirmation != @workspace.name}
            >
              Delete Realm
            </button>
          </form>
        </div>
      </section>
    </div>
    """
  end

  defp storage_pct(used, max) when max > 0, do: round(used / max * 100)
  defp storage_pct(_used, _max), do: 0

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
