defmodule SummonerWeb.AdminLive.Dashboard do
  use SummonerWeb, :live_view

  alias Summoner.Adapters.Persistence.Admin

  @impl true
  def mount(_params, _session, socket) do
    stats = Admin.system_stats()

    {:ok,
     assign(socket,
       page_title: "Admin Dashboard",
       stats: stats,
       smtp_configured?: Admin.smtp_configured?()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <h1 class="text-2xl font-bold">Archon Dashboard</h1>

      <div :if={!@smtp_configured?} class="alert alert-warning">
        <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
        <span>
          Email delivery (SMTP) is not configured. Magic links and email confirmations are disabled.
          Users will register with passwords instead.
        </span>
      </div>

      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
        <div class="stat bg-base-200 rounded-box">
          <div class="stat-title">Users</div>
          <div class="stat-value">{@stats.user_count}</div>
        </div>
        <div class="stat bg-base-200 rounded-box">
          <div class="stat-title">Guilds</div>
          <div class="stat-value">{@stats.tenant_count}</div>
        </div>
        <div class="stat bg-base-200 rounded-box">
          <div class="stat-title">Realms</div>
          <div class="stat-value">{@stats.workspace_count}</div>
        </div>
        <div class="stat bg-base-200 rounded-box">
          <div class="stat-title">Summons</div>
          <div class="stat-value">{@stats.agent_count}</div>
        </div>
        <div class="stat bg-base-200 rounded-box">
          <div class="stat-title">Invocations</div>
          <div class="stat-value">{@stats.invocation_count}</div>
        </div>
      </div>

      <p class="text-sm text-base-content/60">
        Registration is managed per-guild via each guild's settings.
      </p>

      <div class="flex gap-4 flex-wrap">
        <.link navigate="/archon/users" class="btn btn-outline btn-sm">Manage Users</.link>
        <.link navigate="/guilds" class="btn btn-outline btn-sm">Manage Guilds</.link>
        <.link navigate="/archon/realms" class="btn btn-outline btn-sm">
          Manage Realms
        </.link>
        <.link navigate="/archon/invites" class="btn btn-outline btn-sm">
          Manage Invites
        </.link>
        <.link navigate="/archon/quotas" class="btn btn-outline btn-sm">
          Manage Quotas
        </.link>
      </div>
    </div>
    """
  end
end
