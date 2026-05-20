defmodule SummonerWeb.AgentLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.Domain.Policies.WorkspacePolicy
  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.LocalAgent
  alias Summoner.Domain.Types.Presets
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.MediaProviders
  alias Summoner.Ports.Persistence.Providers
  alias Summoner.Ports.Persistence.Workspaces

  @impl true
  def mount(params, _session, socket) do
    workspace = socket.assigns.workspace

    if WorkspacePolicy.can?(socket.assigns.membership, :configure) do
      scope = socket.assigns.current_scope
      providers = Providers.list_providers(scope, workspace.id, workspace.tenant_id)

      {agent, title} =
        case params["id"] do
          nil ->
            settings = Workspaces.get_settings!(workspace.id)

            {%Agent{
               workspace_id: workspace.id,
               local_agent: %LocalAgent{
                 step_timeout_s: settings.default_step_timeout_s,
                 total_timeout_s: settings.default_total_timeout_s
               }
             }, "New Summon"}

          id ->
            {Agents.get_agent!(scope, workspace.id, id), "Edit Summon"}
        end

      local = agent.local_agent || %LocalAgent{}

      flat_data =
        %{
          name: agent.name,
          callname: agent.callname,
          role: agent.role,
          model: local.model,
          provider_id: local.provider_id,
          media_provider_id: local.media_provider_id,
          system_prompt: local.system_prompt,
          personality: local.personality,
          max_steps: local.max_steps,
          max_concurrent_invocations: local.max_concurrent_invocations,
          max_delegation_concurrency: local.max_delegation_concurrency,
          max_tokens_per_invocation: local.max_tokens_per_invocation,
          context_length: local.context_length,
          step_timeout_s: local.step_timeout_s,
          total_timeout_s: local.total_timeout_s,
          stream_tokens_to_observability: local.stream_tokens_to_observability
        }

      changeset = flat_changeset(flat_data, %{})

      breadcrumbs =
        if agent.id do
          [
            {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
            {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
            {"Summons", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/summons"},
            {agent.name,
             ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/summons/#{agent.id}"},
            {"Edit", nil}
          ]
        else
          [
            {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
            {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
            {"Summons", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/summons"},
            {"New Summon", nil}
          ]
        end

      provider_options =
        Enum.map(providers, fn p -> {p.name, p.id} end)

      media_provider_options =
        MediaProviders.list_media_providers(scope, workspace.id, workspace.tenant_id)
        |> Enum.map(fn c -> {c.name, c.id} end)

      initial_provider_id =
        if agent.id, do: to_string(local.provider_id), else: nil

      cached_models =
        load_cached_models(providers, initial_provider_id)

      socket =
        socket
        |> assign(page_title: "#{title} - #{workspace.name}")
        |> assign(
          agent: agent,
          form: to_form(changeset, as: "agent"),
          title: title,
          editing: agent.id != nil,
          providers: providers,
          provider_options: provider_options,
          media_provider_options: media_provider_options,
          model_options: cached_models,
          last_provider_id: initial_provider_id,
          template_options: Presets.agent_options(),
          selected_template: "",
          advanced_open: false
        )
        |> assign(breadcrumbs: breadcrumbs)
        |> maybe_load_models_async(scope, providers, initial_provider_id)

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to do that.")
       |> redirect(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}")}
    end
  end

  @impl true
  def handle_event("validate", %{"agent" => params} = raw, socket) do
    params = maybe_apply_template(params, raw["template"], socket.assigns.selected_template)
    selected = raw["template"] || socket.assigns.selected_template

    changeset =
      flat_changeset(flat_data_from_assigns(socket), params)
      |> Map.put(:action, :validate)

    # Reload models only if provider changed
    scope = socket.assigns.current_scope
    provider_id = params["provider_id"]
    last_provider_id = socket.assigns[:last_provider_id]

    socket =
      if provider_id != last_provider_id do
        cached = load_cached_models(socket.assigns.providers, provider_id)

        socket
        |> assign(model_options: cached)
        |> maybe_load_models_async(scope, socket.assigns.providers, provider_id)
      else
        socket
      end

    {:noreply,
     assign(socket,
       form: to_form(changeset, as: "agent"),
       selected_template: selected,
       last_provider_id: provider_id
     )}
  end

  @impl true
  def handle_event("toggle_advanced", _params, socket) do
    {:noreply, assign(socket, advanced_open: !socket.assigns.advanced_open)}
  end

  @impl true
  def handle_event("save", %{"agent" => params}, socket) do
    if socket.assigns.editing do
      update_agent(socket, params)
    else
      create_agent(socket, params)
    end
  end

  defp maybe_apply_template(params, template_key, last_template)
       when is_binary(template_key) and template_key != "" and template_key != last_template do
    case Presets.agent(template_key) do
      nil ->
        params

      template ->
        Map.merge(params, %{
          "system_prompt" => template.system_prompt,
          "personality" => template.personality
        })
    end
  end

  defp maybe_apply_template(params, _key, _last), do: params

  defp create_agent(socket, params) do
    workspace = socket.assigns.workspace
    params = Map.put(params, "workspace_id", workspace.id)

    case Agents.create_agent(socket.assigns.current_scope, params) do
      {:ok, _agent} ->
        {:noreply,
         socket
         |> put_flash(:info, "Summon summoned successfully.")
         |> push_navigate(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/summons")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> maybe_flash_callname_error(changeset)
         |> assign(form: to_form(changeset, as: "agent"))}
    end
  end

  defp update_agent(socket, params) do
    workspace = socket.assigns.workspace

    case Agents.update_agent(
           socket.assigns.current_scope,
           socket.assigns.agent,
           params
         ) do
      {:ok, agent} ->
        {:noreply,
         socket
         |> put_flash(:info, "Summon updated successfully.")
         |> push_navigate(
           to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/summons/#{agent.id}"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> maybe_flash_callname_error(changeset)
         |> assign(form: to_form(changeset, as: "agent"))}
    end
  end

  defp load_cached_models(_providers, nil), do: []

  defp load_cached_models(providers, provider_id) do
    case Enum.find(providers, fn p -> p.id == provider_id end) do
      nil -> []
      provider -> filter_chat_models(provider.cached_models || [], provider.kind)
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

  @impl true
  def handle_async(:load_models, {:ok, {:ok, models}}, socket) do
    provider_kind = current_provider_kind(socket)
    filtered = filter_chat_models(models, provider_kind)
    {:noreply, assign(socket, model_options: filtered)}
  end

  def handle_async(:load_models, _result, socket) do
    # On error, keep whatever cached models are already assigned
    {:noreply, socket}
  end

  defp current_provider_kind(socket) do
    provider_id = socket.assigns.last_provider_id

    case Enum.find(socket.assigns.providers, fn p -> p.id == provider_id end) do
      nil -> "unknown"
      provider -> provider.kind
    end
  end

  defp filter_chat_models(models, kind) do
    Providers.filter_models_by_capability(models, kind, :chat)
  end

  # ---------------------------------------------------------------
  # Flat (schemaless) changeset for combined agent + local_agent form
  # ---------------------------------------------------------------

  @flat_types %{
    name: :string,
    callname: :string,
    role: :string,
    model: :string,
    provider_id: :string,
    media_provider_id: :string,
    system_prompt: :string,
    personality: :string,
    max_steps: :integer,
    max_concurrent_invocations: :integer,
    max_delegation_concurrency: :integer,
    max_tokens_per_invocation: :integer,
    context_length: :integer,
    step_timeout_s: :integer,
    total_timeout_s: :integer,
    stream_tokens_to_observability: :boolean,
    max_tool_concurrency: :integer
  }

  defp flat_changeset(data, params) do
    {data, @flat_types}
    |> Ecto.Changeset.cast(params, Map.keys(@flat_types))
    |> Ecto.Changeset.validate_required([:name, :role, :model, :provider_id])
  end

  defp flat_data_from_assigns(socket) do
    agent = socket.assigns.agent
    local = agent.local_agent || %LocalAgent{}

    %{
      name: agent.name,
      callname: agent.callname,
      role: agent.role,
      model: local.model,
      provider_id: local.provider_id,
      media_provider_id: local.media_provider_id,
      system_prompt: local.system_prompt,
      personality: local.personality,
      max_steps: local.max_steps,
      max_concurrent_invocations: local.max_concurrent_invocations,
      max_delegation_concurrency: local.max_delegation_concurrency,
      max_tokens_per_invocation: local.max_tokens_per_invocation,
      context_length: local.context_length,
      step_timeout_s: local.step_timeout_s,
      total_timeout_s: local.total_timeout_s,
      stream_tokens_to_observability: local.stream_tokens_to_observability,
      max_tool_concurrency: local.max_tool_concurrency
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <h1 class="text-2xl font-bold">{@title}</h1>

      <.form for={@form} id="agent-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <div :if={!@editing} class="form-control">
          <label class="label">
            <span class="label-text font-medium">Template</span>
          </label>
          <select name="template" class="select select-bordered select-sm w-full">
            {Phoenix.HTML.Form.options_for_select(@template_options, @selected_template)}
          </select>
        </div>

        <.input field={@form[:name]} type="text" label="Name" required phx-debounce="300" />
        <.input
          field={@form[:callname]}
          type="text"
          label="Callname"
          placeholder={if @editing, do: "", else: "Auto-generated from name"}
        />
        <p class="text-xs text-base-content/50 -mt-2">
          Used for @callname routing in partys. Lowercase, snake_case. Auto-generated on first creation if left empty.
        </p>
        <.input
          field={@form[:role]}
          type="select"
          label="Role"
          options={Agent.role_options()}
          required
        />
        <p class="text-xs text-base-content/50 -mt-2">
          {Agent.role_description(Ecto.Changeset.get_field(@form.source, :role))}
        </p>
        <.input
          field={@form[:provider_id]}
          type="select"
          label="Gateway"
          options={@provider_options}
          prompt="Select a gateway"
          required
        />
        <.input
          field={@form[:model]}
          type="text"
          label="Spirit"
          list="model-options"
          required
          placeholder="Type or select a model"
        />
        <datalist id="model-options">
          <option :for={model <- @model_options} value={model}>{model}</option>
        </datalist>
        <.text_editor
          field={@form[:system_prompt]}
          label="Instructions"
          placeholder="Enter system instructions..."
        />
        <.text_editor
          field={@form[:personality]}
          label="Persona"
          placeholder="Enter personality description..."
        />

        <div class="bg-base-200 rounded-box">
          <button
            type="button"
            phx-click="toggle_advanced"
            class="w-full flex items-center justify-between p-4 font-medium cursor-pointer"
          >
            <span>Advanced Settings</span>
            <span class={[
              "transition-transform duration-200",
              @advanced_open && "rotate-180"
            ]}>
              ▼
            </span>
          </button>
          <div :if={@advanced_open} class="px-4 pb-4 space-y-4">
            <.input
              field={@form[:media_provider_id]}
              type="select"
              label="Forge"
              options={@media_provider_options}
              prompt="Workspace default"
            />
            <p class="text-xs text-base-content/50 -mt-2">
              Media generation provider for image generation. Leave as workspace default unless this summon needs a specific provider.
            </p>
            <.input field={@form[:max_steps]} type="number" label="Max Steps" min="1" />
            <.input
              field={@form[:max_concurrent_invocations]}
              type="number"
              label="Max Concurrent Invocations"
              min="1"
            />
            <.input
              field={@form[:max_delegation_concurrency]}
              type="number"
              label="Max Delegation Concurrency"
              min="1"
            />
            <.input
              field={@form[:max_tool_concurrency]}
              type="number"
              label="Max Tool Concurrency"
              placeholder="Inherits workspace default"
              min="1"
            />
            <p class="text-xs text-base-content/50 -mt-2">
              Maximum parallel tool executions per step. Leave blank to use the workspace default.
            </p>
            <.input
              field={@form[:max_tokens_per_invocation]}
              type="number"
              label="Max Tokens per Invocation"
              min="1"
            />
            <.input
              field={@form[:context_length]}
              type="number"
              label="Context Length"
              placeholder="e.g. 8192, 32768, 131072"
            />
            <p class="text-xs text-base-content/50 -mt-2">
              The model's context window size in tokens.
              For local providers this sets num_ctx / n_ctx. Leave blank for default (131072).
            </p>
            <.input
              field={@form[:step_timeout_s]}
              type="number"
              label="Step Timeout (seconds)"
              min="1"
              max="600"
            />
            <.input
              field={@form[:total_timeout_s]}
              type="number"
              label="Total Timeout (seconds)"
              min="1"
              max="3600"
            />
            <.input
              field={@form[:stream_tokens_to_observability]}
              type="checkbox"
              label="Stream tokens to observability"
            />
          </div>
        </div>

        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/summons"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Summon", else: "Summon Summon"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  defp maybe_flash_callname_error(socket, changeset) do
    case Keyword.get(changeset.errors, :callname) do
      {msg, _opts} ->
        put_flash(socket, :error, "Callname #{msg}. Please rename the summon.")

      nil ->
        socket
    end
  end
end
