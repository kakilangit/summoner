defmodule SummonerWeb.ProviderLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.Presets
  alias Summoner.Providers
  alias Summoner.Providers.Provider
  alias Summoner.Secrets
  alias Summoner.Workspaces.Policy

  @impl true
  def mount(params, _session, socket) do
    workspace = socket.assigns.workspace

    if Policy.can?(socket.assigns.membership, :configure) do
      scope = socket.assigns.current_scope

      {provider, title} =
        case params["id"] do
          nil ->
            {%Provider{workspace_id: workspace.id}, "Add Gateway"}

          id ->
            {Providers.get_provider!(scope, workspace.id, workspace.tenant_id, id),
             "Edit Gateway"}
        end

      changeset = Provider.changeset(provider, %{})

      secrets = Secrets.list_secrets(scope, workspace.id, workspace.tenant_id)
      secret_options = Enum.map(secrets, &{&1.name, &1.id})

      socket =
        socket
        |> assign(page_title: "#{title} - #{workspace.name}")
        |> assign(provider: provider, form: to_form(changeset))
        |> assign(title: title, editing: provider.id != nil)
        |> assign(last_kind: to_string(provider.kind || ""))
        |> assign(secret_options: secret_options)
        |> assign(
          breadcrumbs: [
            {"Realms", ~p"/realms/#{workspace.tenant_id}/realms"},
            {workspace.name, ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}"},
            {"Gateways", ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}/gateways"},
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
  def handle_event("validate", %{"provider" => params}, socket) do
    params = maybe_apply_kind_defaults(params, socket.assigns.last_kind)

    changeset =
      socket.assigns.provider
      |> Provider.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(form: to_form(changeset), last_kind: params["kind"])}
  end

  @impl true
  def handle_event("save", %{"provider" => params}, socket) do
    if socket.assigns.editing do
      update_provider(socket, params)
    else
      create_provider(socket, params)
    end
  end

  defp maybe_apply_kind_defaults(params, last_kind) do
    kind = params["kind"]

    if kind != last_kind and kind != "" do
      case Presets.provider(kind) do
        nil ->
          params

        preset ->
          params
          |> Map.merge(%{
            "api_format" => preset.api_format,
            "type" => preset.type
          })
          |> maybe_set_default_url(kind)
      end
    else
      params
    end
  end

  defp maybe_set_default_url(params, kind) do
    current_url = params["base_url"] || ""
    default_urls = Presets.provider_default_urls()

    if current_url == "" or current_url in Presets.provider_default_url_values() do
      Map.put(params, "base_url", Map.get(default_urls, kind, ""))
    else
      params
    end
  end

  defp create_provider(socket, params) do
    workspace = socket.assigns.workspace
    params = Map.put(params, "workspace_id", workspace.id)

    case Providers.create_provider(socket.assigns.current_scope, params) do
      {:ok, provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gateway created successfully.")
         |> push_navigate(
           to: ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}/gateways/#{provider.id}"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_provider(socket, params) do
    workspace = socket.assigns.workspace

    case Providers.update_provider(socket.assigns.current_scope, socket.assigns.provider, params) do
      {:ok, provider} ->
        socket =
          socket
          |> put_flash(:info, "Gateway updated successfully.")
          |> push_navigate(
            to: ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}/gateways/#{provider.id}"
          )

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <h1 class="text-2xl font-bold">{@title}</h1>

      <.form for={@form} id="provider-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <.input field={@form[:name]} type="text" label="Name" required phx-debounce="300" />
        <.input
          field={@form[:kind]}
          type="select"
          label="Kind"
          options={Presets.provider_kind_options()}
          prompt="Select a kind"
          required
        />
        <.input
          field={@form[:api_format]}
          type="select"
          label="API Format"
          options={Provider.api_formats()}
          prompt="Select a format"
          required
        />
        <.input
          field={@form[:type]}
          type="select"
          label="Type"
          options={[{"Local", :local}, {"Cloud", :cloud}]}
          prompt="Select a type"
          required
        />
        <.input field={@form[:base_url]} type="text" label="Base URL" required phx-debounce="300" />
        <.input
          field={@form[:api_key_secret_id]}
          type="select"
          label="API Key (Seal)"
          options={@secret_options}
          prompt="None"
        />
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/realms/#{@workspace.tenant_id}/realms/#{@workspace.id}/gateways"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Gateway", else: "Create Gateway"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end
end
