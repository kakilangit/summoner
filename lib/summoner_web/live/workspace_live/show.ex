defmodule SummonerWeb.WorkspaceLive.Show do
  use SummonerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(page_title: workspace.name)
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, nil}
        ]
      )

    {:ok, socket}
  end

  defp dashboard_card(assigns) do
    ~H"""
    <.link navigate={@navigate} class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow">
      <div class="card-body">
        <div class="flex items-center gap-3">
          <div class="rounded-lg bg-primary/10 p-2">
            <.icon name={@icon} class="size-5 text-primary" />
          </div>
          <div>
            <h2 class="card-title text-base">{@title}</h2>
            <p class="text-sm text-base-content/60">{@description}</p>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">{@workspace.name}</h1>
        <div class="flex gap-2">
          <.link
            navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/settings"}
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
          </.link>
          <.link
            navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/members"}
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-user-group" class="size-4" /> Members
          </.link>
        </div>
      </div>

      <div class="space-y-8">
        <%!-- Daily Flows --%>
        <section>
          <h2 class="text-lg font-semibold mb-3 text-base-content/80">Quests</h2>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <.dashboard_card
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/conversations"
              }
              icon="hero-chat-bubble-left-right"
              title="Channels"
              description="Chat with your Summons"
            />
            <.dashboard_card
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/pipelines"}
              icon="hero-arrow-right-circle"
              title="Quests"
              description="Chain summons in sequence"
            />
            <.dashboard_card
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/artifacts"}
              icon="hero-archive-box"
              title="Relics"
              description="Persistent agent outputs"
            />
            <.dashboard_card
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/approval-rules"
              }
              icon="hero-shield-check"
              title="Rites"
              description="Approval rules for agent actions"
            />
          </div>
        </section>

        <%!-- Base Config --%>
        <section>
          <h2 class="text-lg font-semibold mb-3 text-base-content/80">Realm Foundations</h2>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <.dashboard_card
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/providers"}
              icon="hero-server-stack"
              title="Gateways"
              description="Manage LLM providers"
            />
            <.dashboard_card
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/agents"}
              icon="hero-sparkles"
              title="Summons"
              description="Manage your AI agents"
            />
            <.dashboard_card
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/mcp-servers"}
              icon="hero-command-line"
              title="Runes"
              description="Manage tool servers"
            />
            <.dashboard_card
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/secrets"}
              icon="hero-lock-closed"
              title="Seals"
              description="Manage encrypted secrets"
            />
            <.dashboard_card
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/media-providers"
              }
              icon="hero-paint-brush"
              title="Forges"
              description="Media generation providers"
            />
          </div>
        </section>

        <%!-- Advanced --%>
        <section>
          <h2 class="text-lg font-semibold mb-3 text-base-content/80">Arcana</h2>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <.dashboard_card
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/skills"}
              icon="hero-book-open"
              title="Spellbook"
              description="Knowledge and skills for summons"
            />
            <.dashboard_card
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/swarms"}
              icon="hero-user-group"
              title="Parties"
              description="Multi-agent collaboration swarms"
            />
            <.dashboard_card
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/files"}
              icon="hero-document-text"
              title="Scrolls"
              description="Browse and manage workspace files"
            />
            <.dashboard_card
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/remote-agents"
              }
              icon="hero-globe-alt"
              title="Envoys"
              description="Connect remote A2A agents"
            />
            <.dashboard_card
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/access-tokens"
              }
              icon="hero-key"
              title="Wards"
              description="Manage scoped access tokens"
            />
            <.dashboard_card
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/plugins"}
              icon="hero-puzzle-piece"
              title="Grimoires"
              description="Install and manage plugins"
            />
            <.dashboard_card
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/knowledge-bases"
              }
              icon="hero-academic-cap"
              title="Codex"
              description="Manage knowledge bases for RAG"
            />
          </div>
        </section>
      </div>
    </div>
    """
  end
end
