defmodule SummonerWeb.AgentLive.Show do
  use SummonerWeb, :live_view

  alias Summoner.Agents
  alias Summoner.Agents.Agent
  alias Summoner.Ledger

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope
    agent = Agents.get_agent!(scope, workspace.id, id)
    usage = Ledger.usage_for_agent(agent.id)

    socket =
      socket
      |> assign(page_title: "#{agent.name} - #{workspace.name}")
      |> assign(agent: agent, usage: usage)
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Summons", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/summons"},
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
          navigate={
            ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/summons/#{@agent.id}/edit"
          }
          class="btn btn-primary btn-sm"
        >
          Edit
        </.link>
      </div>

      <div class="space-y-4">
        <div class="flex items-center gap-2">
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
          <span class="text-sm text-base-content/60">{@agent.local_agent.model}</span>
        </div>

        <div
          :if={@agent.local_agent && @agent.local_agent.system_prompt}
          class="collapse collapse-arrow bg-base-200"
        >
          <input type="checkbox" checked />
          <div class="collapse-title text-sm font-medium">Instructions</div>
          <div class="collapse-content text-sm whitespace-pre-wrap">
            {@agent.local_agent.system_prompt}
          </div>
        </div>

        <div
          :if={@agent.local_agent && @agent.local_agent.personality}
          class="collapse collapse-arrow bg-base-200"
        >
          <input type="checkbox" checked />
          <div class="collapse-title text-sm font-medium">Persona</div>
          <div class="collapse-content text-sm whitespace-pre-wrap">
            {@agent.local_agent.personality}
          </div>
        </div>

        <div class="flex gap-2 pt-2">
          <.link
            navigate={
              ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/summons/#{@agent.id}/runes"
            }
            class="btn btn-ghost btn-sm"
          >
            Runes
          </.link>
          <.link
            navigate={
              ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/summons/#{@agent.id}/skills"
            }
            class="btn btn-ghost btn-sm"
          >
            Spellbook
          </.link>
        </div>

        <div class="collapse collapse-arrow bg-base-200">
          <input type="checkbox" />
          <div class="collapse-title font-medium text-sm">Advanced Settings</div>
          <div class="collapse-content">
            <div class="grid grid-cols-2 gap-2 text-sm">
              <div class="text-base-content/60">Max Steps</div>
              <div>{@agent.local_agent.max_steps}</div>
              <div class="text-base-content/60">Max Concurrent</div>
              <div>{@agent.local_agent.max_concurrent_invocations}</div>
              <div class="text-base-content/60">Max Delegation</div>
              <div>{@agent.local_agent.max_delegation_concurrency}</div>
              <div class="text-base-content/60">Token Limit</div>
              <div>{@agent.local_agent.max_tokens_per_invocation}</div>
              <div class="text-base-content/60">Context Length</div>
              <div>{@agent.local_agent.context_length || "Default (131072)"}</div>
              <div class="text-base-content/60">Step Timeout</div>
              <div>{@agent.local_agent.step_timeout_s}s</div>
              <div class="text-base-content/60">Total Timeout</div>
              <div>{@agent.local_agent.total_timeout_s}s</div>
            </div>
          </div>
        </div>

        <.usage_stats usage={@usage} />
      </div>
    </div>
    """
  end

  attr :usage, :map, required: true

  defp usage_stats(%{usage: %{total_tokens: nil}} = assigns) do
    ~H"""
    <div class="text-sm text-base-content/50">No token usage recorded yet.</div>
    """
  end

  defp usage_stats(assigns) do
    ~H"""
    <div class="space-y-2">
      <h3 class="text-sm font-medium">Token Usage</h3>
      <div class="stats stats-vertical sm:stats-horizontal bg-base-200 w-full">
        <div class="stat py-3 px-4">
          <div class="stat-title text-xs">Total Tokens</div>
          <div class="stat-value text-lg">{format_number(@usage.total_tokens)}</div>
        </div>
        <div class="stat py-3 px-4">
          <div class="stat-title text-xs">Prompt</div>
          <div class="stat-value text-lg">{format_number(@usage.prompt_tokens)}</div>
        </div>
        <div class="stat py-3 px-4">
          <div class="stat-title text-xs">Completion</div>
          <div class="stat-value text-lg">{format_number(@usage.completion_tokens)}</div>
        </div>
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
end
