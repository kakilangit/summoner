defmodule SummonerWeb.TenantMediaProviderLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.Adapters.Persistence.MediaProviders
  alias Summoner.Adapters.Persistence.Providers
  alias Summoner.Domain.Schemas.MediaProvider

  @impl true
  def mount(params, _session, socket) do
    tenant = socket.assigns.tenant

    if socket.assigns.tenant_can?.(:manage_resources) do
      providers = Providers.list_tenant_providers(tenant.id)

      {media_provider, title} =
        case params["id"] do
          nil ->
            {%MediaProvider{tenant_id: tenant.id}, "New Forge"}

          id ->
            {MediaProviders.get_tenant_media_provider!(tenant.id, id), "Edit Forge"}
        end

      changeset = MediaProvider.changeset(media_provider, %{})

      provider_options = Enum.map(providers, fn p -> {p.name, p.id} end)

      initial_provider_id =
        if media_provider.id, do: to_string(media_provider.provider_id), else: nil

      image_models = load_cached_image_models(providers, initial_provider_id)

      socket =
        socket
        |> assign(page_title: "#{title} - #{tenant.name}")
        |> assign(
          media_provider: media_provider,
          form: to_form(changeset),
          title: title,
          editing: media_provider.id != nil,
          providers: providers,
          provider_options: provider_options,
          image_model_options: image_models,
          last_provider_id: initial_provider_id
        )
        |> assign(
          breadcrumbs: [
            {"Guilds", ~p"/guilds"},
            {tenant.name, ~p"/guilds/#{tenant.id}/realms"},
            {"Forges", ~p"/guilds/#{tenant.id}/forges"},
            {title, nil}
          ]
        )
        |> maybe_load_models_async(socket.assigns.current_scope, providers, initial_provider_id)

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to do that.")
       |> redirect(to: ~p"/guilds/#{tenant.id}/realms")}
    end
  end

  @impl true
  def handle_event("validate", %{"media_provider" => params}, socket) do
    changeset =
      socket.assigns.media_provider
      |> MediaProvider.changeset(params)
      |> Map.put(:action, :validate)

    scope = socket.assigns.current_scope
    provider_id = params["provider_id"]
    last_provider_id = socket.assigns.last_provider_id

    socket =
      if provider_id != last_provider_id do
        image_models = load_cached_image_models(socket.assigns.providers, provider_id)

        socket
        |> assign(image_model_options: image_models)
        |> maybe_load_models_async(scope, socket.assigns.providers, provider_id)
      else
        socket
      end

    {:noreply, assign(socket, form: to_form(changeset), last_provider_id: provider_id)}
  end

  @impl true
  def handle_event("save", %{"media_provider" => params}, socket) do
    if socket.assigns.editing do
      update_media_provider(socket, params)
    else
      create_media_provider(socket, params)
    end
  end

  @impl true
  def handle_async(:load_models, {:ok, {:ok, models}}, socket) do
    provider_kind = current_provider_kind(socket)
    image_models = Providers.filter_models_by_capability(models, provider_kind, :image)

    {:noreply, assign(socket, image_model_options: image_models)}
  end

  def handle_async(:load_models, _result, socket) do
    {:noreply, socket}
  end

  defp current_provider_kind(socket) do
    provider_id = socket.assigns.last_provider_id

    case Enum.find(socket.assigns.providers, fn p -> p.id == provider_id end) do
      nil -> "unknown"
      provider -> provider.kind
    end
  end

  defp load_cached_image_models(_providers, nil), do: []

  defp load_cached_image_models(providers, provider_id) do
    case Enum.find(providers, fn p -> p.id == provider_id end) do
      nil ->
        []

      provider ->
        Providers.filter_models_by_capability(
          provider.cached_models || [],
          provider.kind,
          :image
        )
    end
  end

  defp maybe_load_models_async(socket, _scope, _providers, nil), do: socket

  defp maybe_load_models_async(socket, scope, providers, provider_id) do
    case Enum.find(providers, fn p -> p.id == provider_id end) do
      nil ->
        socket

      provider ->
        start_async(socket, :load_models, fn ->
          Providers.available_models(scope, provider)
        end)
    end
  end

  defp create_media_provider(socket, params) do
    tenant = socket.assigns.tenant
    params = Map.put(params, "tenant_id", tenant.id)

    case MediaProviders.create_media_provider(socket.assigns.current_scope, params) do
      {:ok, _media_provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Forge created successfully.")
         |> push_navigate(to: ~p"/guilds/#{tenant.id}/forges")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_media_provider(socket, params) do
    tenant = socket.assigns.tenant

    case MediaProviders.update_media_provider(
           socket.assigns.current_scope,
           socket.assigns.media_provider,
           params
         ) do
      {:ok, _media_provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Forge updated successfully.")
         |> push_navigate(to: ~p"/guilds/#{tenant.id}/forges")}

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
        id="media-provider-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input field={@form[:name]} type="text" label="Name" required phx-debounce="300" />
        <.input
          field={@form[:provider_id]}
          type="select"
          label="Gateway"
          options={@provider_options}
          prompt="Select a gateway"
          required
        />
        <.input
          field={@form[:default_image_model]}
          type="text"
          label="Default Image Spirit"
          list="image-spirit-options"
          placeholder="Type or select a spirit"
          phx-debounce="300"
        />
        <datalist id="image-spirit-options">
          <option :for={model <- @image_model_options} value={model}>{model}</option>
        </datalist>
        <.input
          field={@form[:max_concurrent_jobs]}
          type="number"
          label="Max Concurrent Jobs"
          phx-debounce="300"
        />

        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/guilds/#{@tenant.id}/forges"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Forge", else: "Create Forge"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end
end
