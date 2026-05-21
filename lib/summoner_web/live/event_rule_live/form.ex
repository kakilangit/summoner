defmodule SummonerWeb.EventRuleLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.Domain.Policies.WorkspacePolicy
  alias Summoner.Domain.Schemas.EventRule
  alias Summoner.Services.EventRules

  @action_type_options [
    {"Invoke Agent", :invoke_agent},
    {"Run Pipeline", :run_pipeline},
    {"Call Webhook", :call_webhook},
    {"Send Notification", :send_notification}
  ]

  @impl true
  def mount(params, _session, socket) do
    workspace = socket.assigns.workspace

    if WorkspacePolicy.can?(socket.assigns.membership, :configure) do
      scope = socket.assigns.current_scope

      {rule, title} =
        case params["id"] do
          nil ->
            {%EventRule{workspace_id: workspace.id}, "New Omen"}

          id ->
            {EventRules.get_rule!(scope, workspace.id, id), "Edit Omen"}
        end

      changeset = EventRules.change_rule(rule)

      socket =
        socket
        |> assign(page_title: "#{title} - #{workspace.name}")
        |> assign(
          rule: rule,
          form: to_form(changeset),
          title: title,
          editing: rule.id != nil,
          event_types: Enum.map(EventRule.event_types(), &{&1, &1}),
          action_type_options: @action_type_options,
          conditions_json: format_json(rule.conditions),
          action_config_json: format_json(rule.action_config)
        )
        |> assign(
          breadcrumbs: [
            {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
            {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
            {"Omens",
             ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/event-rules"},
            {title, nil}
          ]
        )

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to do that.")
       |> redirect(to: ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}")}
    end
  end

  @impl true
  def handle_event("validate", %{"event_rule" => params}, socket) do
    params = merge_json_fields(params, socket)

    changeset =
      socket.assigns.rule
      |> EventRules.change_rule(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("update_conditions", %{"value" => value}, socket) do
    {:noreply, assign(socket, conditions_json: value)}
  end

  @impl true
  def handle_event("update_action_config", %{"value" => value}, socket) do
    {:noreply, assign(socket, action_config_json: value)}
  end

  @impl true
  def handle_event("save", %{"event_rule" => params}, socket) do
    params = merge_json_fields(params, socket)

    if socket.assigns.editing do
      update_rule(socket, params)
    else
      create_rule(socket, params)
    end
  end

  defp create_rule(socket, params) do
    workspace = socket.assigns.workspace
    params = Map.put(params, "workspace_id", workspace.id)

    case EventRules.create_rule(socket.assigns.current_scope, params) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Omen created.")
         |> push_navigate(
           to: ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/event-rules"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_rule(socket, params) do
    workspace = socket.assigns.workspace

    case EventRules.update_rule(socket.assigns.current_scope, socket.assigns.rule, params) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Omen updated.")
         |> push_navigate(
           to: ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/event-rules"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp merge_json_fields(params, socket) do
    conditions =
      case Jason.decode(socket.assigns.conditions_json) do
        {:ok, decoded} -> decoded
        _ -> %{}
      end

    action_config =
      case Jason.decode(socket.assigns.action_config_json) do
        {:ok, decoded} -> decoded
        _ -> %{}
      end

    params
    |> Map.put("conditions", conditions)
    |> Map.put("action_config", action_config)
  end

  defp format_json(nil), do: "{}"
  defp format_json(map) when map == %{}, do: "{}"
  defp format_json(map), do: Jason.encode!(map, pretty: true)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">{@title}</h1>

      <.form
        for={@form}
        id="event-rule-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input
          field={@form[:name]}
          type="text"
          label="Name"
          placeholder="e.g. Notify on invocation failure"
          required
        />

        <.input
          field={@form[:description]}
          type="text"
          label="Description"
          placeholder="Optional description of what this omen does"
        />

        <.input
          field={@form[:event_type]}
          type="select"
          label="Event Type"
          options={@event_types}
          prompt="Select event type"
          required
        />

        <div>
          <label class="label"><span class="label-text">Conditions (JSON)</span></label>
          <textarea
            name="conditions_json"
            phx-change="update_conditions"
            phx-debounce="300"
            class="textarea textarea-bordered w-full font-mono text-sm"
            rows="6"
            placeholder={~s|{"all": [{"field": "agent.name", "op": "eq", "value": "myagent"}]}|}
          >{@conditions_json}</textarea>
          <p class="text-xs text-base-content/50 mt-1">
            JSON condition DSL. Use <code>all</code>, <code>any</code>, <code>none</code>
            combinators with operators: eq, neq, in, contains, gt, lt, gte, lte, exists, matches.
          </p>
        </div>

        <.input
          field={@form[:action_type]}
          type="select"
          label="Action Type"
          options={@action_type_options}
          prompt="Select action type"
          required
        />

        <div>
          <label class="label"><span class="label-text">Action Config (JSON)</span></label>
          <textarea
            name="action_config_json"
            phx-change="update_action_config"
            phx-debounce="300"
            class="textarea textarea-bordered w-full font-mono text-sm"
            rows="6"
            placeholder={~s|{"agent_id": "...", "prompt": "Handle: {{event.type}}"}|}
          >{@action_config_json}</textarea>
          <p class="text-xs text-base-content/50 mt-1">
            JSON config for the action. Use <code>{"{{field.path}}"}</code> for template interpolation.
          </p>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:cooldown_s]}
            type="number"
            label="Cooldown (seconds)"
            min="0"
            max="86400"
          />

          <.input
            field={@form[:priority]}
            type="number"
            label="Priority"
            min="0"
            max="1000"
          />
        </div>

        <.input
          field={@form[:enabled]}
          type="checkbox"
          label="Enabled"
        />

        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/event-rules"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Omen", else: "Create Omen"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end
end
