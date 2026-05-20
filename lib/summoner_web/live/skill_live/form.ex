defmodule SummonerWeb.SkillLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Skills
  alias Summoner.Domain.Policies.WorkspacePolicy
  alias Summoner.Domain.Schemas.Skill
  alias Summoner.Domain.Types.Presets

  @impl true
  def mount(params, _session, socket) do
    workspace = socket.assigns.workspace

    if WorkspacePolicy.can?(socket.assigns.membership, :configure) do
      scope = socket.assigns.current_scope

      {skill, title} =
        case params["id"] do
          nil ->
            {%Skill{workspace_id: workspace.id}, "New Spell"}

          id ->
            {Skills.get_skill!(scope, workspace.id, workspace.tenant_id, id), "Edit Spell"}
        end

      changeset = Skill.changeset(skill, %{})

      socket =
        socket
        |> assign(page_title: "#{title} - #{workspace.name}")
        |> assign(
          skill: skill,
          form: to_form(changeset),
          title: title,
          editing: skill.id != nil,
          template_options: Presets.skill_options(),
          selected_template: ""
        )
        |> assign(
          breadcrumbs: [
            {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
            {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
            {"Spellbook", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/spells"},
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
  def handle_event("validate", %{"skill" => params} = raw, socket) do
    params = maybe_apply_template(params, raw["template"], socket.assigns.selected_template)
    selected = raw["template"] || socket.assigns.selected_template

    changeset =
      socket.assigns.skill
      |> Skill.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset), selected_template: selected)}
  end

  @impl true
  def handle_event("save", %{"skill" => params}, socket) do
    if socket.assigns.editing do
      update_skill(socket, params)
    else
      create_skill(socket, params)
    end
  end

  defp maybe_apply_template(params, template_key, last_template)
       when is_binary(template_key) and template_key != "" and template_key != last_template do
    case Presets.skill(template_key) do
      nil ->
        params

      template ->
        Map.merge(params, %{
          "name" => template.name,
          "content" => template.content
        })
    end
  end

  defp maybe_apply_template(params, _key, _last), do: params

  defp create_skill(socket, params) do
    workspace = socket.assigns.workspace
    params = Map.put(params, "workspace_id", workspace.id)

    case Skills.create_skill(socket.assigns.current_scope, params) do
      {:ok, _skill} ->
        {:noreply,
         socket
         |> put_flash(:info, "Spell created.")
         |> push_navigate(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/spells")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_skill(socket, params) do
    workspace = socket.assigns.workspace

    case Skills.update_skill(socket.assigns.current_scope, socket.assigns.skill, params) do
      {:ok, _skill} ->
        {:noreply,
         socket
         |> put_flash(:info, "Spell updated.")
         |> push_navigate(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/spells")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto space-y-6">
      <h1 class="text-2xl font-bold">{@title}</h1>

      <.form
        for={@form}
        id="skill-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <div class="flex flex-col sm:flex-row gap-4">
          <div :if={!@editing} class="sm:w-1/2">
            <.input
              type="select"
              name="template"
              value={@selected_template}
              label="Template"
              options={@template_options}
            />
          </div>

          <div class={[!@editing && "sm:w-1/2", @editing && "w-full"]}>
            <.input
              field={@form[:name]}
              type="text"
              label="Name"
              placeholder="elixir-basics"
              required
            />
          </div>
        </div>

        <.text_editor
          field={@form[:content]}
          label="Content"
          placeholder="Knowledge or instructions for the summon..."
        />

        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/spells"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Spell", else: "Create Spell"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end
end
