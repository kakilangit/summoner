defmodule SummonerWeb.A2AClientLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.Adapters.Persistence.Agents
  alias Summoner.Adapters.Persistence.Secrets
  alias Summoner.Domain.Policies.WorkspacePolicy
  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.RemoteAgent

  @impl true
  def mount(params, _session, socket) do
    workspace = socket.assigns.workspace

    if WorkspacePolicy.can?(socket.assigns.membership, :configure) do
      scope = socket.assigns.current_scope

      {agent, title} =
        case params["id"] do
          nil ->
            {%Agent{type: :remote, workspace_id: workspace.id, remote_agent: %RemoteAgent{}},
             "New Envoy"}

          id ->
            {Agents.get_agent!(scope, workspace.id, id), "Edit Envoy"}
        end

      secrets = Secrets.list_secrets(scope, workspace.id, workspace.tenant_id)
      changeset = flat_changeset(flat_data(agent), %{})

      socket =
        socket
        |> assign(page_title: "#{title} - #{workspace.name}")
        |> assign(
          agent: agent,
          form: to_form(changeset, as: "agent"),
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
  def handle_event("validate", %{"agent" => params}, socket) do
    changeset =
      flat_changeset(flat_data(socket.assigns.agent), params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "agent"))}
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
        {:noreply,
         socket
         |> maybe_flash_callname_error(changeset)
         |> assign(form: to_form(changeset, as: "agent"))}
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
        {:noreply,
         socket
         |> maybe_flash_callname_error(changeset)
         |> assign(form: to_form(changeset, as: "agent"))}
    end
  end

  # -------------------------------------------------------------------
  # Flat (schemaless) changeset for combined Agent + RemoteAgent form
  # -------------------------------------------------------------------

  @flat_types %{
    name: :string,
    agent_card_url: :string,
    auth_mode: :string,
    api_key_secret_id: :string,
    timeout_s: :integer
  }

  defp flat_changeset(data, params) do
    {data, @flat_types}
    |> Ecto.Changeset.cast(params, Map.keys(@flat_types))
    |> Ecto.Changeset.validate_required([:name, :agent_card_url])
  end

  defp flat_data(agent) do
    remote = agent.remote_agent || %RemoteAgent{}

    %{
      name: agent.name,
      agent_card_url: remote.agent_card_url,
      auth_mode: remote.auth_mode,
      api_key_secret_id: remote.api_key_secret_id,
      timeout_s: remote.timeout_s
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <h1 class="text-2xl font-bold">{@title}</h1>

      <.form
        for={@form}
        id="envoy-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input field={@form[:name]} type="text" label="Name" placeholder="My Remote Agent" required />

        <.input
          field={@form[:agent_card_url]}
          type="url"
          label="Agent Card URL"
          placeholder="https://agent.example.com"
          required
        />
        <p class="text-xs text-base-content/50 -mt-2">
          Base URL of the remote A2A agent (without <code>/.well-known/agent-card.json</code>).
          The agent card will be discovered automatically.
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

  defp maybe_flash_callname_error(socket, changeset) do
    case Keyword.get(changeset.errors, :callname) do
      {msg, _opts} ->
        put_flash(socket, :error, "Callname #{msg}. Please rename the envoy.")

      nil ->
        socket
    end
  end
end
