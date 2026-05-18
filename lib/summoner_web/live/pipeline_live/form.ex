defmodule SummonerWeb.PipelineLive.Form do
  use SummonerWeb, :live_view

  alias Phoenix.HTML.Form
  alias Summoner.Agents
  alias Summoner.Pipelines
  alias Summoner.Pipelines.{CronBuilder, Pipeline}
  alias Summoner.Workspaces.Policy

  @impl true
  def mount(params, _session, socket) do
    workspace = socket.assigns.workspace

    if Policy.can?(socket.assigns.membership, :configure) do
      scope = socket.assigns.current_scope
      agents = Agents.list_agents(scope, workspace.id)

      {pipeline, title} =
        case params["id"] do
          nil ->
            {%Pipeline{workspace_id: workspace.id, stages: []}, "New Quest"}

          id ->
            {Pipelines.get_pipeline!(scope, workspace.id, id), "Edit Quest"}
        end

      changeset = Pipeline.changeset(pipeline, %{})
      agent_options = Enum.map(agents, fn a -> {a.name, a.id} end)
      agents_by_id = Map.new(agents, &{&1.id, &1})

      manager_agents =
        agents
        |> Enum.filter(&(&1.role == :autonomous))
        |> Enum.map(fn a -> {a.name, a.id} end)

      socket =
        socket
        |> assign(page_title: "#{title} - #{workspace.name}")
        |> assign(
          pipeline: pipeline,
          form: to_form(changeset),
          title: title,
          editing: pipeline.id != nil,
          agent_options: agent_options,
          agents_by_id: agents_by_id,
          manager_options: manager_agents,
          stages: pipeline.stages,
          # Pending stages for new quests (not yet persisted)
          pending_stages: [],
          stage_form_key: 0,
          show_advanced: false,
          schedule_preset: schedule_preset_for(pipeline)
        )
        |> assign(
          breadcrumbs: [
            {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
            {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
            {"Quests", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/quests"},
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
  def handle_event("validate", %{"pipeline" => params}, socket) do
    changeset =
      socket.assigns.pipeline
      |> Pipeline.changeset(params)
      |> Map.put(:action, :validate)

    # Sync preset when cron expression changes via direct input
    preset =
      if params["trigger_type"] in ["scheduled", :scheduled] do
        sync_preset(socket.assigns.schedule_preset, params["cron_expression"])
      else
        socket.assigns.schedule_preset
      end

    {:noreply, socket |> assign(form: to_form(changeset), schedule_preset: preset)}
  end

  @impl true
  def handle_event("toggle_advanced", _params, socket) do
    {:noreply, assign(socket, show_advanced: !socket.assigns.show_advanced)}
  end

  @impl true
  def handle_event("schedule_preset_changed", %{"preset" => preset_value}, socket) do
    socket =
      if preset_value == "custom" do
        assign(socket, schedule_preset: "custom")
      else
        # preset_value is the cron expression itself
        changeset =
          socket.assigns.pipeline
          |> Pipeline.changeset(%{
            "cron_expression" => preset_value,
            "trigger_type" => "scheduled"
          })
          |> Map.put(:action, :validate)

        socket
        |> assign(schedule_preset: preset_value)
        |> assign(form: to_form(changeset))
      end

    {:noreply, socket}
  end

  # --- New quest: manage pending stages in memory ---

  @impl true
  def handle_event("add_pending_stage", %{"agent_id" => agent_id} = params, socket)
      when agent_id != "" do
    instruction = Map.get(params, "instruction", "")
    agent = Map.get(socket.assigns.agents_by_id, agent_id)

    if agent do
      stage = %{
        id: System.unique_integer([:positive]),
        agent_id: agent_id,
        agent: agent,
        instruction: instruction,
        position: length(socket.assigns.pending_stages)
      }

      pending = socket.assigns.pending_stages ++ [stage]

      {:noreply,
       assign(socket, pending_stages: pending, stage_form_key: socket.assigns.stage_form_key + 1)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_pending_stage", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("remove_pending_stage", %{"idx" => idx_str}, socket) do
    idx = String.to_integer(idx_str)

    pending =
      socket.assigns.pending_stages
      |> List.delete_at(idx)
      |> Enum.with_index()
      |> Enum.map(fn {s, i} -> %{s | position: i} end)

    {:noreply, assign(socket, pending_stages: pending)}
  end

  # --- Save (new) ---

  @impl true
  def handle_event("save", %{"pipeline" => params}, socket) do
    if socket.assigns.editing do
      update_pipeline(socket, params)
    else
      create_pipeline(socket, params)
    end
  end

  # --- Editing: persisted stage management ---

  @impl true
  def handle_event("add_stage", %{"agent_id" => agent_id} = params, socket)
      when agent_id != "" do
    scope = socket.assigns.current_scope
    pipeline = socket.assigns.pipeline

    if pipeline.id do
      position = length(socket.assigns.stages)
      instruction = Map.get(params, "instruction", "")

      case Pipelines.add_stage(scope, %{
             pipeline_id: pipeline.id,
             agent_id: agent_id,
             position: position,
             instruction: instruction
           }) do
        {:ok, _stage} ->
          stages = Pipelines.list_stages(pipeline.id)
          {:noreply, socket |> assign(stages: stages) |> put_flash(:info, "Phase added.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not add phase.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Save the quest first before adding phases.")}
    end
  end

  def handle_event("add_stage", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event(
        "save_instruction",
        %{"stage_id" => stage_id, "instruction" => instruction} = params,
        socket
      ) do
    scope = socket.assigns.current_scope
    stage = Enum.find(socket.assigns.stages, &(&1.id == stage_id))

    if stage do
      depends_on =
        params
        |> Map.get("depends_on_positions", [])
        |> List.wrap()
        |> Enum.map(&String.to_integer/1)

      attrs = %{instruction: instruction, depends_on_positions: depends_on}

      case Pipelines.update_stage(scope, stage, attrs) do
        {:ok, _} ->
          stages = Pipelines.list_stages(socket.assigns.pipeline.id)
          {:noreply, socket |> assign(stages: stages) |> put_flash(:info, "Instruction saved.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not update instruction.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_stage", %{"id" => stage_id}, socket) do
    scope = socket.assigns.current_scope
    pipeline = socket.assigns.pipeline
    stage = Enum.find(socket.assigns.stages, &(&1.id == stage_id))

    if stage do
      case Pipelines.remove_stage(scope, stage) do
        {:ok, _} ->
          stages = Pipelines.list_stages(pipeline.id)
          {:noreply, socket |> assign(stages: stages) |> put_flash(:info, "Phase removed.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not remove phase.")}
      end
    else
      {:noreply, socket}
    end
  end

  # --- Private ---

  defp create_pipeline(socket, params) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope
    params = Map.put(params, "workspace_id", workspace.id)

    case Pipelines.create_pipeline(scope, params) do
      {:ok, pipeline} ->
        # Persist all pending stages
        Enum.each(socket.assigns.pending_stages, fn stage ->
          Pipelines.add_stage(scope, %{
            pipeline_id: pipeline.id,
            agent_id: stage.agent_id,
            position: stage.position,
            instruction: stage.instruction
          })
        end)

        {:noreply,
         socket
         |> put_flash(:info, "Quest created.")
         |> push_navigate(
           to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/quests/#{pipeline.id}"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_pipeline(socket, params) do
    workspace = socket.assigns.workspace

    case Pipelines.update_pipeline(socket.assigns.current_scope, socket.assigns.pipeline, params) do
      {:ok, _pipeline} ->
        {:noreply,
         socket
         |> put_flash(:info, "Quest updated.")
         |> push_navigate(to: ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/quests")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto space-y-6">
      <h1 class="text-2xl font-bold">{@title}</h1>

      <.form
        for={@form}
        id="pipeline-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input field={@form[:name]} type="text" label="Name" required phx-debounce="300" />

        <.input
          field={@form[:trigger_type]}
          type="select"
          label="Trigger"
          options={Pipeline.trigger_types()}
          required
        />

        <div :if={show_cron?(@form)} class="space-y-3">
          <div class="form-control">
            <label class="label">
              <span class="label-text">Schedule</span>
            </label>
            <select
              name="preset"
              phx-change="schedule_preset_changed"
              class="select select-bordered select-sm w-full"
            >
              {preset_select_options(@schedule_preset)}
            </select>
          </div>

          <div :if={@schedule_preset == "custom"} class="space-y-1">
            <.input
              field={@form[:cron_expression]}
              type="text"
              label="Cron Expression"
              placeholder="*/5 * * * *"
            />
            <p class="text-xs text-base-content/50">
              Standard 5-field cron: minute hour day month weekday
            </p>
          </div>

          <div :if={@schedule_preset != "custom"}>
            <input type="hidden" name="pipeline[cron_expression]" value={@schedule_preset} />
            <p class="text-xs text-base-content/50">
              <span class="font-mono">{@schedule_preset}</span>
            </p>
          </div>
        </div>

        <%!-- Advanced options --%>
        <div class="pt-2">
          <button
            type="button"
            phx-click="toggle_advanced"
            class="text-xs text-base-content/50 hover:text-base-content/70 flex items-center gap-1"
          >
            <span class={[
              "hero-chevron-right size-3 transition-transform",
              @show_advanced && "rotate-90"
            ]}>
            </span>
            Advanced options
          </button>

          <div :if={@show_advanced} class="mt-3 space-y-4 pl-4 border-l-2 border-base-300">
            <.input
              field={@form[:mode]}
              type="select"
              label="Mode"
              options={Pipeline.modes()}
              required
            />

            <div :if={show_orchestrator?(@form)}>
              <.input
                field={@form[:orchestrator_agent_id]}
                type="select"
                label="Orchestrator Summon"
                options={@manager_options}
                prompt="Select a manager summon"
              />
              <p :if={@manager_options == []} class="text-xs text-error mt-1">
                No autonomous summons found. Create one first.
              </p>
            </div>
          </div>
        </div>

        <div class="flex items-center justify-end gap-3 pt-2">
          <.link
            navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/quests"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Quest", else: "Create Quest"}
          </.button>
        </div>
      </.form>

      <%!-- New quest: pending stages (in-memory) --%>
      <div :if={!@editing} class="space-y-4 border-t border-base-300 pt-6">
        <h2 class="text-lg font-semibold">Phases</h2>

        <div :if={@pending_stages == []} class="text-sm text-base-content/60 py-4 text-center">
          Add summons below to define the quest sequence.
        </div>

        <div class="space-y-2">
          <div
            :for={{stage, idx} <- Enum.with_index(@pending_stages)}
            class="flex items-center gap-3 p-3 bg-base-200 rounded-lg"
          >
            <span class="badge badge-neutral badge-sm font-mono">#{idx + 1}</span>
            <div class="flex-1 min-w-0">
              <span class="font-medium text-sm">{stage.agent.name}</span>
              <span class="text-xs text-base-content/50 ml-2">{stage.agent.model}</span>
              <p :if={stage.instruction != ""} class="text-xs text-base-content/60 mt-0.5 truncate">
                {stage.instruction}
              </p>
            </div>
            <button
              type="button"
              phx-click="remove_pending_stage"
              phx-value-idx={idx}
              class="btn btn-error btn-xs btn-outline"
            >
              Remove
            </button>
          </div>
        </div>

        <form
          id={"add-phase-form-#{@stage_form_key}"}
          phx-submit="add_pending_stage"
          class="space-y-3 p-4 border border-dashed border-base-300 rounded-lg"
        >
          <p class="text-sm font-medium text-base-content/70">Add Phase</p>
          <div class="form-control">
            <label class="label">
              <span class="label-text text-xs">Summon</span>
            </label>
            <select name="agent_id" class="select select-bordered select-sm w-full">
              <option value="">Select a summon</option>
              {Phoenix.HTML.Form.options_for_select(@agent_options, nil)}
            </select>
          </div>
          <div class="form-control">
            <.text_editor
              id={"new-pending-instruction-#{@stage_form_key}"}
              name="instruction"
              value=""
              label="Instruction"
              placeholder="What should this summon do at this step?"
              rows={6}
            />
          </div>
          <div class="flex justify-end">
            <button type="submit" class="btn btn-secondary btn-sm">
              <span class="hero-plus size-4"></span> Add Phase
            </button>
          </div>
        </form>
      </div>

      <%!-- Editing: persisted stages --%>
      <div :if={@editing} class="space-y-4 border-t border-base-300 pt-6">
        <h2 class="text-lg font-semibold">Phases</h2>

        <div :if={@stages == []} class="text-sm text-base-content/60 py-4 text-center">
          No phases yet. Add summons below to define the quest sequence.
        </div>

        <div class="space-y-3">
          <div
            :for={stage <- @stages}
            class="bg-base-200 rounded-lg overflow-hidden"
          >
            <div class="flex items-center justify-between px-4 py-2.5 border-b border-base-300/50">
              <div class="flex items-center gap-3">
                <span class="badge badge-neutral badge-sm font-mono">
                  #{stage.position + 1}
                </span>
                <div>
                  <span class="font-medium">{stage.agent.name}</span>
                  <div class="text-sm text-base-content/60">{stage.agent.model}</div>
                </div>
                <span
                  :if={stage.depends_on_positions != [] && stage.depends_on_positions != nil}
                  class="text-xs text-base-content/50"
                >
                  after {Enum.map_join(stage.depends_on_positions, ", ", &"##{&1 + 1}")}
                </span>
                <span
                  :if={
                    stage.position > 0 &&
                      (stage.depends_on_positions == [] || stage.depends_on_positions == nil)
                  }
                  class="text-xs text-base-content/40"
                >
                  after #{stage.position}
                </span>
              </div>
              <button
                phx-click={show_confirm("#remove-stage-#{stage.id}")}
                class="btn btn-error btn-xs btn-outline"
              >
                Remove
              </button>
              <.confirm_modal
                id={"remove-stage-#{stage.id}"}
                title="Remove phase?"
                message="This phase will be removed from the quest."
                confirm_text="Remove"
                on_confirm={JS.push("remove_stage", value: %{id: stage.id})}
              />
            </div>
            <form phx-submit="save_instruction" class="px-4 py-3 space-y-3">
              <input type="hidden" name="stage_id" value={stage.id} />
              <.text_editor
                id={"stage-instruction-#{stage.id}"}
                name="instruction"
                value={stage.instruction}
                label="Instruction"
                placeholder="What should this summon do at this step?"
                rows={8}
              />

              <%!-- Dependency selector --%>
              <div :if={stage.position > 0} class="rounded-md bg-base-300/40 px-3 py-2">
                <p class="text-xs font-medium text-base-content/60 mb-1.5">
                  Depends on
                  <span class="text-base-content/40">(none = sequential after previous)</span>
                </p>
                <div class="flex flex-wrap gap-x-4 gap-y-1.5">
                  <label
                    :for={other <- Enum.filter(@stages, &(&1.position < stage.position))}
                    class="inline-flex items-center gap-1.5 cursor-pointer select-none"
                  >
                    <input
                      type="checkbox"
                      name="depends_on_positions[]"
                      value={other.position}
                      checked={other.position in (stage.depends_on_positions || [])}
                      class="checkbox checkbox-xs checkbox-primary"
                    />
                    <span class="text-xs text-base-content/80">
                      <span class="font-mono text-base-content/50">#{other.position + 1}</span>
                      {other.agent.name}
                    </span>
                  </label>
                </div>
              </div>

              <div class="flex justify-end">
                <button type="submit" class="btn btn-ghost btn-xs">
                  <span class="hero-check size-3.5"></span> Save
                </button>
              </div>
            </form>
          </div>
        </div>

        <form
          phx-submit="add_stage"
          class="space-y-3 p-4 border border-dashed border-base-300 rounded-lg"
        >
          <p class="text-sm font-medium text-base-content/70">Add Phase</p>
          <div class="form-control">
            <label class="label">
              <span class="label-text text-xs">Summon</span>
            </label>
            <select name="agent_id" class="select select-bordered select-sm w-full">
              <option value="">Select a summon</option>
              {Phoenix.HTML.Form.options_for_select(@agent_options, nil)}
            </select>
          </div>
          <div class="form-control">
            <.text_editor
              id="new-stage-instruction"
              name="instruction"
              value=""
              label="Instruction"
              placeholder="What should this summon do?"
              rows={8}
            />
          </div>
          <div class="flex justify-end">
            <button type="submit" class="btn btn-secondary btn-sm">
              <span class="hero-plus size-4"></span> Add Phase
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp show_orchestrator?(form) do
    Form.input_value(form, :mode) in ["orchestrated", :orchestrated]
  end

  defp show_cron?(form) do
    Form.input_value(form, :trigger_type) in ["scheduled", :scheduled]
  end

  defp schedule_preset_for(%Pipeline{cron_expression: nil}), do: "*/5 * * * *"
  defp schedule_preset_for(%Pipeline{cron_expression: ""}), do: "*/5 * * * *"

  defp schedule_preset_for(%Pipeline{cron_expression: cron}) do
    case CronBuilder.preset_for(cron) do
      "custom" -> "custom"
      _key -> cron
    end
  end

  defp sync_preset("custom", _cron), do: "custom"

  defp sync_preset(current, cron) when is_binary(cron) do
    case CronBuilder.preset_for(cron) do
      "custom" -> current
      _key -> cron
    end
  end

  defp sync_preset(current, _), do: current

  defp preset_select_options(current_value) do
    options = CronBuilder.preset_options()
    Form.options_for_select(options, current_value)
  end
end
