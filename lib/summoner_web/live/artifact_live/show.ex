defmodule SummonerWeb.ArtifactLive.Show do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Artifacts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope
    artifact = Artifacts.get_artifact!(scope, workspace.id, id)
    versions = Artifacts.list_versions(workspace.id, id)

    socket =
      socket
      |> assign(
        page_title: "#{artifact.name} - Relic",
        artifact: artifact,
        versions: versions
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Relics", ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/artifacts"},
          {artifact.name, nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_pin", _params, socket) do
    scope = socket.assigns.current_scope
    artifact = socket.assigns.artifact

    case Artifacts.update_artifact(scope, artifact, %{pinned: !artifact.pinned}) do
      {:ok, updated} -> {:noreply, assign(socket, artifact: updated)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update relic.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold flex items-center gap-2">
            {@artifact.name}
            <span class="badge badge-ghost">{@artifact.type}</span>
            <span class="badge badge-ghost">v{@artifact.version}</span>
            <span :if={@artifact.pinned} class="badge badge-warning">pinned</span>
          </h1>
          <p class="text-sm text-base-content/60 mt-1">
            {Atom.to_string(@artifact.content_type)} · Created {Calendar.strftime(
              @artifact.inserted_at,
              "%Y-%m-%d %H:%M"
            )} · Updated {Calendar.strftime(@artifact.updated_at, "%Y-%m-%d %H:%M")}
          </p>
        </div>
        <div class="flex gap-2">
          <button phx-click="toggle_pin" class="btn btn-ghost btn-sm">
            {if @artifact.pinned, do: "Unpin", else: "Pin"}
          </button>
          <.link
            href={
              ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/artifacts/#{@artifact.id}/download"
            }
            class="btn btn-ghost btn-sm"
          >
            Export
          </.link>
        </div>
      </div>

      <div class="bg-base-200 rounded-lg p-6">
        <div class="prose prose-sm max-w-none">
          <pre :if={code_type?(@artifact.content_type)}><code>{@artifact.content}</code></pre>
          <div :if={!code_type?(@artifact.content_type)} class="whitespace-pre-wrap">
            {@artifact.content}
          </div>
        </div>
      </div>

      <div :if={length(@versions) > 1} class="space-y-2">
        <h2 class="text-lg font-semibold">Version History</h2>
        <div class="space-y-1">
          <div
            :for={version <- @versions}
            class={[
              "flex items-center justify-between p-3 rounded-lg",
              if(version.id == @artifact.id,
                do: "bg-primary/10 border border-primary/20",
                else: "bg-base-200"
              )
            ]}
          >
            <div class="flex items-center gap-2">
              <span class="font-medium">v{version.version}</span>
              <span class="text-sm text-base-content/60">
                {Calendar.strftime(version.inserted_at, "%Y-%m-%d %H:%M")}
              </span>
            </div>
            <.link
              :if={version.id != @artifact.id}
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/artifacts/#{version.id}"
              }
              class="btn btn-ghost btn-xs"
            >
              View
            </.link>
          </div>
        </div>
      </div>

      <div :if={@artifact.metadata != %{}} class="space-y-2">
        <h2 class="text-lg font-semibold">Metadata</h2>
        <div class="bg-base-200 rounded-lg p-4">
          <pre class="text-sm">{Jason.encode!(@artifact.metadata, pretty: true)}</pre>
        </div>
      </div>
    </div>
    """
  end

  defp code_type?(content_type) do
    content_type in ~w(
      text/x-elixir text/x-python text/javascript text/typescript
      application/json text/css text/html text/x-rust text/x-go
      text/x-java text/x-c text/x-cpp text/x-ruby text/x-shell
      text/plain
    )
  end
end
