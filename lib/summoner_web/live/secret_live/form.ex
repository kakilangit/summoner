defmodule SummonerWeb.SecretLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.Secrets
  alias Summoner.Secrets.Secret
  alias Summoner.Workspaces.Policy

  @impl true
  def mount(params, _session, socket) do
    workspace = socket.assigns.workspace

    if Policy.can?(socket.assigns.membership, :configure) do
      scope = socket.assigns.current_scope

      {secret, title} =
        case params["id"] do
          nil ->
            {%Secret{workspace_id: workspace.id}, "New Seal"}

          id ->
            {Secrets.get_secret!(scope, workspace.id, workspace.tenant_id, id), "Edit Seal"}
        end

      changeset = Secret.changeset(secret, %{})

      socket =
        socket
        |> assign(page_title: "#{title} - #{workspace.name}")
        |> assign(
          secret: secret,
          form: to_form(changeset),
          title: title,
          editing: secret.id != nil
        )
        |> assign(
          breadcrumbs: [
            {"Realms", ~p"/realms/#{workspace.tenant_id}/realms"},
            {workspace.name, ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}"},
            {"Seals", ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}/seals"},
            {title, nil}
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
  def handle_event("save", %{"secret" => params}, socket) do
    if socket.assigns.editing do
      update_secret(socket, params)
    else
      create_secret(socket, params)
    end
  end

  defp create_secret(socket, params) do
    workspace = socket.assigns.workspace
    params = Map.put(params, "workspace_id", workspace.id)

    case Secrets.create_secret(socket.assigns.current_scope, params) do
      {:ok, _secret} ->
        {:noreply,
         socket
         |> put_flash(:info, "Seal created.")
         |> push_navigate(to: ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}/seals")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_secret(socket, params) do
    workspace = socket.assigns.workspace

    case Secrets.update_secret(socket.assigns.current_scope, socket.assigns.secret, params) do
      {:ok, _secret} ->
        {:noreply,
         socket
         |> put_flash(:info, "Seal updated.")
         |> push_navigate(to: ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}/seals")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <h1 class="text-2xl font-bold">{@title}</h1>

      <.form
        for={@form}
        id="secret-form"
        phx-submit="save"
        class="space-y-4"
      >
        <.input
          field={@form[:name]}
          type="text"
          label="Name"
          placeholder="GITHUB_TOKEN"
          required
        />
        <p class="text-xs text-base-content/50 -mt-2">
          Uppercase letters, digits, underscores. Referenced as $NAME in rune configs.
        </p>

        <.input
          field={@form[:encrypted_value]}
          type="password"
          label="Value"
          placeholder={if @editing, do: "Leave blank to keep current value", else: ""}
          required={!@editing}
        />

        <.input
          field={@form[:description]}
          type="text"
          label="Description (optional)"
          phx-debounce="300"
        />

        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/realms/#{@workspace.tenant_id}/realms/#{@workspace.id}/seals"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Seal", else: "Create Seal"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end
end
