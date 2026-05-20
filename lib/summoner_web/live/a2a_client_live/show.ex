defmodule SummonerWeb.A2AClientLive.Show do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Ledger
  alias Summoner.Domain.Schemas.Agent

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope
    agent = Agents.get_agent!(scope, workspace.id, id)
    usage = Ledger.usage_for_agent(agent.id)

    remote = agent.remote_agent

    socket =
      socket
      |> assign(page_title: "#{agent.name} - #{workspace.name}")
      |> assign(agent: agent, remote: remote, usage: usage)
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Envoys", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/envoys"},
          {agent.name, nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">{@agent.name}</h1>
        <.link
          :if={@can?.(:configure)}
          navigate={
            ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/envoys/#{@agent.id}/edit"
          }
          class="btn btn-primary btn-sm"
        >
          Edit
        </.link>
      </div>

      <div class="space-y-4">
        <div class="flex items-center gap-2">
          <span class={["badge badge-sm", status_badge(@remote)]}>
            {@remote.status}
          </span>
          <span class="badge badge-ghost badge-sm">{@remote.auth_mode}</span>
          <span
            class={[
              "badge badge-sm",
              @agent.role == :worker && "badge-info",
              @agent.role == :autonomous && "badge-success"
            ]}
            title={Agent.role_description(@agent.role)}
          >
            {@agent.role}
          </span>
        </div>

        <div class="bg-base-200 rounded-box p-4 space-y-3">
          <div class="grid grid-cols-[auto,1fr] gap-x-4 gap-y-2 text-sm">
            <div class="text-base-content/60">Agent Card URL</div>
            <div class="font-mono text-xs break-all">{@remote.agent_card_url}</div>

            <div class="text-base-content/60">Timeout</div>
            <div>{@remote.timeout_s}s</div>

            <div :if={@remote.card_refreshed_at} class="text-base-content/60">Card Refreshed</div>
            <div :if={@remote.card_refreshed_at} class="text-xs">
              {Calendar.strftime(@remote.card_refreshed_at, "%Y-%m-%d %H:%M:%S UTC")}
            </div>
          </div>
        </div>

        <.cached_card_section card={@remote.cached_agent_card} />

        <.usage_stats usage={@usage} />
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Cached agent card
  # -------------------------------------------------------------------

  attr :card, :any, required: true

  defp cached_card_section(%{card: nil} = assigns) do
    ~H"""
    <div class="text-sm text-base-content/50">No cached agent card yet.</div>
    """
  end

  defp cached_card_section(assigns) do
    ~H"""
    <div class="collapse collapse-arrow bg-base-200">
      <input type="checkbox" />
      <div class="collapse-title text-sm font-medium">Cached Agent Card</div>
      <div class="collapse-content">
        <div class="grid grid-cols-[auto,1fr] gap-x-4 gap-y-2 text-sm">
          <div :if={@card["name"]} class="text-base-content/60">Name</div>
          <div :if={@card["name"]}>{@card["name"]}</div>

          <div :if={@card["description"]} class="text-base-content/60">Description</div>
          <div :if={@card["description"]} class="text-xs">{@card["description"]}</div>

          <div :if={@card["url"]} class="text-base-content/60">Service URL</div>
          <div :if={@card["url"]} class="font-mono text-xs break-all">{@card["url"]}</div>

          <div :if={@card["version"]} class="text-base-content/60">Version</div>
          <div :if={@card["version"]}>{@card["version"]}</div>
        </div>

        <div :if={skills(@card) != []} class="mt-3">
          <div class="text-sm font-medium mb-1">Skills</div>
          <div class="space-y-1">
            <div :for={skill <- skills(@card)} class="text-xs bg-base-300 rounded p-2">
              <span class="font-medium">{skill["name"] || skill["id"]}</span>
              <span :if={skill["description"]} class="text-base-content/60 ml-1">
                — {skill["description"]}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp skills(%{"skills" => skills}) when is_list(skills), do: skills
  defp skills(_), do: []

  # -------------------------------------------------------------------
  # Usage stats
  # -------------------------------------------------------------------

  attr :usage, :map, required: true

  defp usage_stats(%{usage: %{total_tokens: nil}} = assigns) do
    ~H"""
    <div class="text-sm text-base-content/50">No usage recorded yet.</div>
    """
  end

  defp usage_stats(assigns) do
    ~H"""
    <div class="space-y-2">
      <h3 class="text-sm font-medium">Usage</h3>
      <div class="stats stats-vertical sm:stats-horizontal bg-base-200 w-full">
        <div class="stat py-3 px-4">
          <div class="stat-title text-xs">Invocations</div>
          <div class="stat-value text-lg">{format_number(@usage.invocation_count)}</div>
        </div>
      </div>
    </div>
    """
  end

  defp format_number(nil), do: "0"

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(n), do: to_string(n)

  defp status_badge(%{status: :online}), do: "badge-success"
  defp status_badge(%{status: :offline}), do: "badge-error"
  defp status_badge(_), do: "badge-ghost"
end
