defmodule SummonerWeb.A2AClientLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.Adapters.Persistence.Agents
  alias Summoner.Adapters.Persistence.Secrets
  alias Summoner.Domain.Policies.WorkspacePolicy
  alias Summoner.Domain.Schemas.Agent

  @impl true
  def mount(params, _session, socket) do
    workspace = socket.assigns.workspace

    if WorkspacePolicy.can?(socket.assigns.membership, :configure) do
      scope = socket.assigns.current_scope

      {agent, title} =
        case params["id"] do
          nil ->
            {%Agent{type: :remote, workspace_id: workspace.id}, "New Envoy"}

          id ->
            {Agents.get_agent!(scope, workspace.id, id), "Edit Envoy"}
        end

      changeset = Agents.change_agent(agent)
      secrets = Secrets.list_secrets(scope, workspace.id, workspace.tenant_id)

      socket =
        socket
        |> assign(page_title: "#{title} - #{workspace.name}")
        |> assign(
          agent: agent,
          form: to_form(changeset),
          title: title,
          editing: agent.id != nil,
          secrets: secrets
        )
        |> assign(
          breadcrumbs: [
            {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
            {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
            {"Envoys", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/envoys"},
            {title, nil}
          ]
        )

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to do that.")
       |> redirect(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}")}
    end
  end

  @impl true
  def handle_event("save", %{"agent" => params}, socket) do
    if socket.assigns.editing do
      update_envoy(socket, params)
    else
      create_envoy(socket, params)
    end
  end

  defp create_envoy(socket, params) do
    workspace = socket.assigns.workspace
    params = Map.put(params, "workspace_id", workspace.id)

    case Agents.create_remote_agent(socket.assigns.current_scope, params) do
      {:ok, _agent} ->
        {:noreply,
         socket
         |> put_flash(:info, "Envoy created.")
         |> push_navigate(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/envoys")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_envoy(socket, params) do
    workspace = socket.assigns.workspace

    case Agents.update_remote_agent(
           socket.assigns.current_scope,
           socket.assigns.agent,
           params
         ) do
      {:ok, _agent} ->
        {:noreply,
         socket
         |> put_flash(:info, "Envoy updated.")
         |> push_navigate(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/envoys")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <h1 class="text-2xl font-bold">{@title}</h1>

      <.form for={@form} id="envoy-form" phx-submit="save" class="space-y-4">
        <.input field={@form[:name]} type="text" label="Name" placeholder="My Remote Agent" required />

        <.input
          field={@form[:agent_card_url]}
          type="url"
          label="Agent Card URL"
          placeholder="https://agent.example.com"
          required
        />
        <p class="text-xs text-base-content/50 -mt-2">
          Base URL of the remote A2A agent. The agent card will be fetched from <code>/.well-known/agent-card.json</code>.
        </p>

        <.input
          field={@form[:auth_mode]}
          type="select"
          label="Authentication"
          options={[
            {"None", "none"},
            {"Bearer Token", "bearer_token"},
            {"API Key", "api_key"}
          ]}
        />

        <.input
          field={@form[:api_key_secret_id]}
          type="select"
          label="Credential (Seal)"
          options={Enum.map(@secrets, &{&1.name, &1.id})}
          prompt="Select a seal..."
        />
        <p class="text-xs text-base-content/50 -mt-2">
          Secret containing the token or API key for authentication.
        </p>

        <.input
          field={@form[:timeout_s]}
          type="number"
          label="Timeout (seconds)"
          placeholder="300"
        />

        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/envoys"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Envoy", else: "Create Envoy"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end
end
