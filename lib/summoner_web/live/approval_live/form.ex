defmodule SummonerWeb.ApprovalLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.Domain.Policies.WorkspacePolicy
  alias Summoner.Domain.Schemas.ApprovalRule
  alias Summoner.Ports.Persistence.Approvals

  @impl true
  def mount(params, _session, socket) do
    workspace = socket.assigns.workspace

    if WorkspacePolicy.can?(socket.assigns.membership, :configure) do
      scope = socket.assigns.current_scope

      {rule, title} =
        case params["id"] do
          nil ->
            {%ApprovalRule{workspace_id: workspace.id}, "New Rite"}

          id ->
            {Approvals.get_rule!(scope, workspace.id, id), "Edit Rite"}
        end

      changeset = Approvals.change_rule(rule)

      socket =
        socket
        |> assign(page_title: "#{title} - #{workspace.name}")
        |> assign(
          rule: rule,
          form: to_form(changeset),
          title: title,
          editing: rule.id != nil,
          trigger_types: ApprovalRule.trigger_types(),
          timeout_actions: ApprovalRule.timeout_actions()
        )
        |> assign(
          breadcrumbs: [
            {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
            {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
            {"Rites",
             ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/approval-rules"},
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
  def handle_event("validate", %{"approval_rule" => params}, socket) do
    changeset =
      socket.assigns.rule
      |> Approvals.change_rule(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"approval_rule" => params}, socket) do
    if socket.assigns.editing do
      update_rule(socket, params)
    else
      create_rule(socket, params)
    end
  end

  defp create_rule(socket, params) do
    workspace = socket.assigns.workspace
    params = Map.put(params, "workspace_id", workspace.id)

    case Approvals.create_rule(socket.assigns.current_scope, params) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rite created.")
         |> push_navigate(
           to: ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/approval-rules"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_rule(socket, params) do
    workspace = socket.assigns.workspace

    case Approvals.update_rule(socket.assigns.current_scope, socket.assigns.rule, params) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rite updated.")
         |> push_navigate(
           to: ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/approval-rules"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">{@title}</h1>

      <.form
        for={@form}
        id="approval-rule-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input
          field={@form[:name]}
          type="text"
          label="Name"
          placeholder="e.g. Require approval for shell commands"
          required
        />

        <.input
          field={@form[:trigger_type]}
          type="select"
          label="Trigger Type"
          options={@trigger_types}
          prompt="Select trigger type"
          required
        />

        <.input
          field={@form[:trigger_config]}
          type="textarea"
          label="Trigger Config (JSON)"
          placeholder={~s|{"tool_names": ["bash"]}|}
          phx-debounce="300"
        />
        <p class="text-xs text-base-content/50 -mt-2">
          JSON object configuring when this trigger fires.
        </p>

        <.input
          field={@form[:approver_roles]}
          type="text"
          label="Approver Roles"
          placeholder="admin, operator"
          phx-debounce="300"
        />
        <p class="text-xs text-base-content/50 -mt-2">
          Comma-separated list of roles allowed to approve.
        </p>

        <.input
          field={@form[:timeout_s]}
          type="number"
          label="Timeout (seconds)"
          min="1"
          max="86400"
        />

        <.input
          field={@form[:timeout_action]}
          type="select"
          label="Timeout Action"
          options={@timeout_actions}
        />

        <.input
          field={@form[:enabled]}
          type="checkbox"
          label="Enabled"
        />

        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/approval-rules"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Rite", else: "Create Rite"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end
end
