defmodule SummonerWeb.ProviderLive.Show do
  use SummonerWeb, :live_view

  alias Summoner.Adapters.Persistence.Ledger
  alias Summoner.Adapters.Persistence.Providers
  alias Summoner.Domain.Types.Presets
  alias Summoner.Ports.Events

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope
    provider = Providers.get_provider!(scope, workspace.id, workspace.tenant_id, id)
    usage = Ledger.usage_for_provider(provider.id)
    model_usage = Ledger.usage_by_model_for_provider(provider.id)

    if connected?(socket) do
      Events.subscribe({:provider, workspace.id, provider.id})
    end

    socket =
      socket
      |> assign(page_title: "#{provider.name} - #{workspace.name}")
      |> assign(provider: provider, usage: usage, model_usage: model_usage)
      |> assign(copilot_connect: nil)
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Gateways", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/gateways"},
          {provider.name, nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("copilot_connect", _params, socket) do
    provider = socket.assigns.provider

    case Providers.start_copilot_connect(provider) do
      {:ok, device_flow} ->
        {:noreply, assign(socket, copilot_connect: {:pending, device_flow})}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(copilot_connect: nil)
         |> put_flash(:error, "Failed to start device flow: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info(%Summoner.Domain.Events.CopilotConnected{}, socket) do
    # Reload provider to pick up the new Seal link
    scope = socket.assigns.current_scope
    workspace = socket.assigns.workspace

    provider =
      Providers.get_provider!(
        scope,
        workspace.id,
        workspace.tenant_id,
        socket.assigns.provider.id
      )

    {:noreply,
     socket
     |> assign(provider: provider, copilot_connect: :connected)
     |> put_flash(:info, "Copilot connected successfully. Seal created and linked.")}
  end

  @impl true
  def handle_info(%Summoner.Domain.Events.CopilotConnectionFailed{reason: reason}, socket) do
    message =
      case reason do
        :expired -> "Device code expired. Please try again."
        :denied -> "Authorization denied by user."
        :polling_timeout -> "Timed out waiting for authorization."
        _ -> "Connection failed: #{inspect(reason)}"
      end

    {:noreply,
     socket
     |> assign(copilot_connect: {:error, message})
     |> put_flash(:error, message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">{@provider.name}</h1>
        <.link
          navigate={
            ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/gateways/#{@provider.id}/edit"
          }
          class="btn btn-primary btn-sm"
        >
          Edit
        </.link>
      </div>

      <div class="space-y-4">
        <div class="flex items-center gap-2">
          <span class={[
            "badge badge-sm",
            @provider.status == :online && "badge-success",
            @provider.status == :offline && "badge-error",
            @provider.status == :unknown && "badge-warning badge-outline"
          ]}>
            {@provider.status}
          </span>
          <span class="badge badge-sm badge-ghost">{provider_kind_label(@provider.kind)}</span>
          <span class="badge badge-sm badge-ghost">{@provider.type}</span>
        </div>

        <div class="grid grid-cols-2 gap-2 text-sm">
          <div class="text-base-content/60">Base URL</div>
          <div class="truncate" title={@provider.base_url}>{@provider.base_url}</div>
          <div class="text-base-content/60">API Format</div>
          <div>{@provider.api_format}</div>
          <div class="text-base-content/60">API Key (Seal)</div>
          <div>
            {if @provider.api_key_secret, do: @provider.api_key_secret.name, else: "None"}
          </div>
        </div>

        <.copilot_connect_section
          :if={@provider.kind == "github-copilot"}
          provider={@provider}
          copilot_connect={@copilot_connect}
        />

        <.usage_stats usage={@usage} />

        <div :if={@model_usage != []} class="space-y-2">
          <h3 class="text-sm font-medium">Usage by Spirit</h3>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Spirit</th>
                  <th class="text-right">Invocations</th>
                  <th class="text-right">Tokens</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @model_usage}>
                  <td class="font-mono text-xs">{row.model}</td>
                  <td class="text-right">{format_number(row.invocation_count)}</td>
                  <td class="text-right">{format_number(row.total_tokens)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div :if={@provider.cached_models != []} class="collapse collapse-arrow bg-base-200">
          <input type="checkbox" />
          <div class="collapse-title text-sm font-medium">
            Cached Spirits ({length(@provider.cached_models)})
          </div>
          <div class="collapse-content">
            <div class="text-xs font-mono space-y-0.5 max-h-48 overflow-y-auto">
              <div :for={model <- @provider.cached_models}>{model}</div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Copilot connect component
  # -------------------------------------------------------------------

  attr :provider, :map, required: true
  attr :copilot_connect, :any, required: true

  defp copilot_connect_section(%{copilot_connect: nil, provider: provider} = assigns) do
    assigns = assign(assigns, has_seal: provider.api_key_secret != nil)

    ~H"""
    <div class="bg-base-200 rounded-lg p-4 space-y-2">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-medium">GitHub Copilot</h3>
        <button phx-click="copilot_connect" class="btn btn-sm btn-primary">
          {if @has_seal, do: "Reconnect", else: "Connect"}
        </button>
      </div>
      <p :if={@has_seal} class="text-xs text-success">
        Connected via {@provider.api_key_secret.name}
      </p>
      <p :if={!@has_seal} class="text-xs text-base-content/60">
        Click Connect to authorize via GitHub device code flow.
      </p>
    </div>
    """
  end

  defp copilot_connect_section(%{copilot_connect: {:pending, device_flow}} = assigns) do
    assigns = assign(assigns, device_flow: device_flow)

    ~H"""
    <div class="bg-base-200 rounded-lg p-4 space-y-3">
      <h3 class="text-sm font-medium">Authorize GitHub Copilot</h3>
      <div class="space-y-2">
        <p class="text-sm">
          Visit
          <a href={@device_flow.verification_uri} target="_blank" class="link link-primary">
            {@device_flow.verification_uri}
          </a>
          and enter:
        </p>
        <div class="flex items-center gap-2">
          <code class="bg-base-300 px-3 py-2 rounded text-lg font-bold tracking-widest select-all">
            {@device_flow.user_code}
          </code>
        </div>
        <p class="text-xs text-base-content/60">
          <span class="loading loading-spinner loading-xs"></span> Waiting for authorization...
        </p>
      </div>
    </div>
    """
  end

  defp copilot_connect_section(%{copilot_connect: :connected} = assigns) do
    ~H"""
    <div class="bg-base-200 rounded-lg p-4">
      <p class="text-sm text-success">Connected successfully.</p>
    </div>
    """
  end

  defp copilot_connect_section(%{copilot_connect: {:error, message}} = assigns) do
    assigns = assign(assigns, message: message)

    ~H"""
    <div class="bg-base-200 rounded-lg p-4 space-y-2">
      <p class="text-sm text-error">{@message}</p>
      <button phx-click="copilot_connect" class="btn btn-sm btn-primary">Try Again</button>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

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

  defp provider_kind_label(kind) do
    case Presets.provider(kind) do
      %{label: label} -> label
      _ -> kind
    end
  end
end
