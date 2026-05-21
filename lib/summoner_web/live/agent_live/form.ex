defmodule SummonerWeb.AgentLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.Domain.Policies.Failover, as: FailoverPolicy
  alias Summoner.Domain.Policies.WorkspacePolicy
  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.LocalAgent
  alias Summoner.Domain.Types.Presets
  alias Summoner.Ports.Persistence.A2A, as: SummonerA2A
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
          stream_tokens_to_observability: local.stream_tokens_to_observability,
          failover_strategy: agent.failover_strategy || :auto,
          failover_delay_ms: agent.failover_delay_ms || 0,
          max_failover_depth: agent.max_failover_depth || 3
        }

      changeset = flat_changeset(flat_data, %{})

      breadcrumbs = build_breadcrumbs(workspace, agent)

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
        |> assign_failover_chain(agent, scope, workspace.id)
        |> load_herald(agent)
        |> maybe_load_models_async(scope, providers, initial_provider_id)

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to do that.")
       |> redirect(to: ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}")}
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

  @impl true
  def handle_event("add_failover", %{"backup_agent_id" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("add_failover", %{"backup_agent_id" => backup_id}, socket) do
    agent = socket.assigns.agent

    case Agents.add_failover_entry(agent.id, backup_id) do
      {:ok, _entry} ->
        {:noreply, reload_failover_chain(socket)}

      {:error, :chain_limit_reached} ->
        {:noreply, put_flash(socket, :error, "Failover chain limit reached (max 10).")}

      {:error, %Ecto.Changeset{} = cs} ->
        msg = changeset_error_message(cs)
        {:noreply, put_flash(socket, :error, "Could not add backup: #{msg}")}
    end
  end

  @impl true
  def handle_event("remove_failover", %{"id" => entry_id}, socket) do
    case Agents.remove_failover_entry(entry_id) do
      :ok ->
        {:noreply,
         socket |> reload_failover_chain() |> put_flash(:info, "Backup removed from chain.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove backup.")}
    end
  end

  @impl true
  def handle_event("reorder_failover", %{"ids" => ids}, socket) when is_list(ids) do
    agent = socket.assigns.agent

    case Agents.reorder_failover_chain(agent.id, ids) do
      :ok ->
        {:noreply, reload_failover_chain(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not reorder chain.")}
    end
  end

  @impl true
  def handle_event("toggle_herald", _params, socket) do
    agent = socket.assigns.agent
    workspace = socket.assigns.workspace

    case socket.assigns.herald do
      nil ->
        {:ok, server} =
          SummonerA2A.create_server(%{
            agent_id: agent.id,
            workspace_id: workspace.id,
            access_mode: :public
          })

        {:noreply,
         socket
         |> assign(herald: server)
         |> put_flash(:info, "Herald enabled.")}

      server ->
        {:ok, _} = SummonerA2A.delete_server(server)

        {:noreply,
         socket
         |> assign(herald: nil)
         |> put_flash(:info, "Herald disabled.")}
    end
  end

  @impl true
  def handle_event("toggle_access_mode", _params, socket) do
    herald = socket.assigns.herald
    new_mode = if herald.access_mode == :public, do: :protected, else: :public
    {:ok, updated} = SummonerA2A.update_server(herald, %{access_mode: new_mode})
    {:noreply, assign(socket, herald: updated)}
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
         |> push_navigate(
           to: ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/agents"
         )}

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
           to: ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/agents/#{agent.id}"
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

  defp build_breadcrumbs(workspace, agent) do
    base = [
      {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
      {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
      {"Summons", ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/agents"}
    ]

    if agent.id do
      base ++
        [
          {agent.name,
           ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/agents/#{agent.id}"},
          {"Edit", nil}
        ]
    else
      base ++ [{"New Summon", nil}]
    end
  end

  defp assign_failover_chain(socket, agent, scope, workspace_id) do
    if agent.id do
      chain = Agents.list_failover_chain(agent.id)
      chain_ids = MapSet.new(chain, & &1.backup_agent_id)

      get_chain_fn = fn id -> Agents.list_failover_chain(id) end

      backup_options =
        Agents.list_agents(scope, workspace_id)
        |> Enum.reject(fn a ->
          a.id == agent.id || a.deleted_at || MapSet.member?(chain_ids, a.id) ||
            FailoverPolicy.creates_cycle?(agent.id, a.id, get_chain_fn)
        end)
        |> Enum.map(fn a -> {"@#{a.callname || a.name}", a.id} end)

      assign(socket, failover_chain: chain, backup_options: backup_options)
    else
      assign(socket, failover_chain: [], backup_options: [])
    end
  end

  defp reload_failover_chain(socket) do
    agent = socket.assigns.agent
    scope = socket.assigns.current_scope
    workspace_id = socket.assigns.workspace.id
    assign_failover_chain(socket, agent, scope, workspace_id)
  end

  defp load_herald(socket, agent) do
    if agent.id do
      herald = SummonerA2A.get_server_by_agent_id(agent.id)
      assign(socket, herald: herald)
    else
      assign(socket, herald: nil)
    end
  end

  defp changeset_error_message(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, errors} -> "#{field} #{Enum.join(errors, ", ")}" end)
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
    max_tool_concurrency: :integer,
    failover_strategy: :string,
    failover_delay_ms: :integer,
    max_failover_depth: :integer
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
      max_tool_concurrency: local.max_tool_concurrency,
      failover_strategy: agent.failover_strategy || :auto,
      failover_delay_ms: agent.failover_delay_ms || 0,
      max_failover_depth: agent.max_failover_depth || 3
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto space-y-6">
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
            <div class="grid grid-cols-2 gap-4">
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
            </div>
            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:max_tool_concurrency]}
                type="number"
                label="Max Tool Concurrency"
                placeholder="Inherits workspace default"
                min="1"
              />
              <.input
                field={@form[:max_tokens_per_invocation]}
                type="number"
                label="Max Tokens per Invocation"
                min="1"
              />
            </div>
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
            <div class="grid grid-cols-2 gap-4">
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
            </div>
            <.input
              field={@form[:stream_tokens_to_observability]}
              type="checkbox"
              label="Stream tokens to observability"
            />
            <div class="divider text-xs text-base-content/40">Failover</div>
            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:failover_strategy]}
                type="select"
                label="Failover Strategy"
                options={[
                  {"Auto", "auto"},
                  {"Manual", "manual"},
                  {"Notify then Auto", "notify_then_auto"}
                ]}
              />
              <.input
                field={@form[:max_failover_depth]}
                type="number"
                label="Max Failover Depth"
                min="1"
                max="10"
              />
            </div>
            <p class="text-xs text-base-content/50 -mt-2">
              Auto: immediately switch to backup. Manual: pause and wait for approval.
              Notify then Auto: notify, wait delay, then switch. Depth: max backups to try (default 3).
            </p>
            <.input
              :if={
                to_string(Ecto.Changeset.get_field(@form.source, :failover_strategy)) ==
                  "notify_then_auto"
              }
              field={@form[:failover_delay_ms]}
              type="number"
              label="Failover Delay (ms)"
              min="0"
              max="300000"
            />
          </div>
        </div>

        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/agents"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Summon", else: "Summon Summon"}
          </.button>
        </div>
      </.form>

      <%!-- Failover chain management (only when editing) --%>
      <div :if={@editing} class="space-y-4">
        <h2 class="text-lg font-semibold">Failover Chain</h2>
        <p class="text-sm text-base-content/60">
          Backup summons are tried in order when the primary fails with a provider error.
        </p>

        <div :if={@failover_chain == []} class="text-sm text-base-content/60">
          No backups configured. Add summons to the failover chain.
        </div>

        <div
          class="space-y-2"
          id="failover-chain-list"
          phx-hook="Sortable"
          data-sortable-event="reorder_failover"
        >
          <div
            :for={entry <- @failover_chain}
            data-sortable-id={entry.id}
            draggable="true"
            class="flex items-center justify-between p-3 bg-base-200 rounded-lg cursor-grab active:cursor-grabbing"
          >
            <div class="flex items-center gap-3 min-w-0 flex-1">
              <span class="hero-bars-3 size-5 text-base-content/30 flex-shrink-0"></span>
              <div class="min-w-0">
                <div class="flex items-center gap-2">
                  <.link
                    navigate={
                      ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/agents/#{entry.backup_agent_id}"
                    }
                    class="font-medium link link-hover truncate"
                  >
                    {entry.backup_agent.name}
                  </.link>
                </div>
                <div
                  :if={entry.backup_agent.local_agent}
                  class="text-sm text-base-content/60 truncate"
                >
                  {entry.backup_agent.local_agent.model}
                </div>
              </div>
            </div>
            <button
              phx-click={show_confirm("#remove-failover-#{entry.id}")}
              class="btn btn-error btn-xs btn-outline"
            >
              Remove
            </button>
            <.confirm_modal
              id={"remove-failover-#{entry.id}"}
              title="Remove backup?"
              message={"Remove #{entry.backup_agent.name} from the failover chain?"}
              confirm_text="Remove"
              on_confirm={JS.push("remove_failover", value: %{id: entry.id})}
            />
          </div>
        </div>

        <form phx-submit="add_failover">
          <div class="fieldset mb-2">
            <label for="backup-agent-select">
              <span class="label mb-1">Add Backup Summon</span>
            </label>
            <div class="flex items-center gap-2 w-full">
              <select id="backup-agent-select" name="backup_agent_id" class="select flex-1">
                <option value="">Select a summon</option>
                {Phoenix.HTML.Form.options_for_select(@backup_options, nil)}
              </select>
              <button type="submit" class="btn btn-secondary">Add</button>
            </div>
          </div>
        </form>
      </div>

      <%!-- Herald management (only when editing) --%>
      <div :if={@editing} class="space-y-4 pb-8">
        <h2 class="text-lg font-semibold">Herald (A2A)</h2>
        <p class="text-sm text-base-content/60">
          Expose this summon as a remote A2A agent.
        </p>

        <div :if={!@herald} class="flex items-center justify-between">
          <span class="text-sm text-base-content/60">Herald is not enabled.</span>
          <button phx-click="toggle_herald" class="btn btn-primary btn-sm">
            Enable
          </button>
        </div>

        <div :if={@herald} class="space-y-3">
          <div class="text-xs font-mono bg-base-300 p-2 rounded select-all overflow-x-auto">
            {herald_url(@agent)}
          </div>

          <div class="flex items-center justify-between">
            <span class="text-sm">Access</span>
            <button phx-click="toggle_access_mode" class="btn btn-xs btn-ghost">
              <span class={"badge badge-sm #{if @herald.access_mode == :public, do: "badge-warning", else: "badge-success"}"}>
                {@herald.access_mode}
              </span>
            </button>
          </div>

          <div class="flex justify-end">
            <button phx-click="toggle_herald" class="btn btn-error btn-sm btn-outline">
              Disable Herald
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp herald_url(agent) do
    "#{SummonerWeb.Endpoint.url()}/agents/#{agent.id}"
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
