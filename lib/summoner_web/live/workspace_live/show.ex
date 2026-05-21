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
            Settings
          </.link>
          <.link
            navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/members"}
            class="btn btn-ghost btn-sm"
          >
            Members
          </.link>
        </div>
      </div>

      <div class="space-y-8">
        <%!-- Daily Flows --%>
        <section>
          <h2 class="text-lg font-semibold mb-3 text-base-content/80">Quests</h2>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <.link
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/conversations"
              }
              class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
            >
              <div class="card-body">
                <h2 class="card-title">Channels</h2>
                <p class="text-sm text-base-content/60">Chat with your Summons</p>
              </div>
            </.link>

            <.link
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/pipelines"}
              class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
            >
              <div class="card-body">
                <h2 class="card-title">Quests</h2>
                <p class="text-sm text-base-content/60">Chain summons in sequence</p>
              </div>
            </.link>
          </div>
        </section>

        <%!-- Base Config --%>
        <section>
          <h2 class="text-lg font-semibold mb-3 text-base-content/80">Realm Foundations</h2>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <.link
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/providers"}
              class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
            >
              <div class="card-body">
                <h2 class="card-title">Gateways</h2>
                <p class="text-sm text-base-content/60">Manage LLM providers</p>
              </div>
            </.link>

            <.link
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/agents"}
              class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
            >
              <div class="card-body">
                <h2 class="card-title">Summons</h2>
                <p class="text-sm text-base-content/60">Manage your AI agents</p>
              </div>
            </.link>

            <.link
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/mcp_servers"}
              class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
            >
              <div class="card-body">
                <h2 class="card-title">Runes</h2>
                <p class="text-sm text-base-content/60">Manage tool servers</p>
              </div>
            </.link>

            <.link
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/secrets"}
              class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
            >
              <div class="card-body">
                <h2 class="card-title">Seals</h2>
                <p class="text-sm text-base-content/60">Manage encrypted secrets</p>
              </div>
            </.link>

            <.link
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/media_providers"
              }
              class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
            >
              <div class="card-body">
                <h2 class="card-title">Forges</h2>
                <p class="text-sm text-base-content/60">Media generation providers</p>
              </div>
            </.link>
          </div>
        </section>

        <%!-- Advanced --%>
        <section>
          <h2 class="text-lg font-semibold mb-3 text-base-content/80">Arcana</h2>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <.link
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/skills"}
              class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
            >
              <div class="card-body">
                <h2 class="card-title">Spellbook</h2>
                <p class="text-sm text-base-content/60">Knowledge and skills for summons</p>
              </div>
            </.link>

            <.link
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/swarms"}
              class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
            >
              <div class="card-body">
                <h2 class="card-title">Partys</h2>
                <p class="text-sm text-base-content/60">Group summons into swarms</p>
              </div>
            </.link>

            <.link
              navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/files"}
              class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
            >
              <div class="card-body">
                <h2 class="card-title">Scrolls</h2>
                <p class="text-sm text-base-content/60">Browse and manage workspace files</p>
              </div>
            </.link>

            <.link
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/remote_agents"
              }
              class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
            >
              <div class="card-body">
                <h2 class="card-title">Envoys</h2>
                <p class="text-sm text-base-content/60">Connect remote A2A agents</p>
              </div>
            </.link>

            <.link
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/access_tokens"
              }
              class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
            >
              <div class="card-body">
                <h2 class="card-title">Wards</h2>
                <p class="text-sm text-base-content/60">Access tokens for protected Heralds</p>
              </div>
            </.link>
          </div>
        </section>
      </div>
    </div>
    """
  end
end
