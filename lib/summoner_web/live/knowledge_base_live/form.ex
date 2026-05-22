defmodule SummonerWeb.KnowledgeBaseLive.Form do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Domain.Schemas.KnowledgeBase
  alias Summoner.Ports.Persistence.KnowledgeBases

  @impl true
  def mount(%{"workspace_id" => _workspace_id} = params, _session, socket) do
    workspace = socket.assigns.workspace

    {kb, changeset, action} =
      case params do
        %{"id" => id} ->
          kb = KnowledgeBases.get_knowledge_base!(workspace.id, id)
          {kb, KnowledgeBase.changeset(kb, %{}), :edit}

        _ ->
          kb = %KnowledgeBase{workspace_id: workspace.id}
          {kb, KnowledgeBase.changeset(kb, %{type: :documents}), :new}
      end

    breadcrumbs = [
      {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
      {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
      {"Codex", ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/knowledge-bases"},
      {if(action == :new, do: "New", else: kb.name), nil}
    ]

    socket =
      socket
      |> assign(:page_title, if(action == :new, do: "New Codex", else: "Edit #{kb.name}"))
      |> assign(:kb, kb)
      |> assign(:changeset, changeset)
      |> assign(:action, action)
      |> assign(:breadcrumbs, breadcrumbs)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"knowledge_base" => params}, socket) do
    changeset =
      socket.assigns.kb
      |> KnowledgeBase.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("save", %{"knowledge_base" => params}, socket) do
    authorize(socket, :configure, fn ->
      save_kb(socket, socket.assigns.action, params)
    end)
  end

  defp save_kb(socket, :new, params) do
    workspace = socket.assigns.workspace

    case KnowledgeBases.create_knowledge_base(workspace.id, params) do
      {:ok, kb} ->
        {:noreply,
         socket
         |> put_flash(:info, "Codex created.")
         |> push_navigate(
           to:
             ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/knowledge-bases/#{kb.id}"
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_kb(socket, :edit, params) do
    workspace = socket.assigns.workspace

    case KnowledgeBases.update_knowledge_base(socket.assigns.kb, params) do
      {:ok, kb} ->
        {:noreply,
         socket
         |> put_flash(:info, "Codex updated.")
         |> push_navigate(
           to:
             ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/knowledge-bases/#{kb.id}"
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">{@page_title}</h1>

      <.form for={@changeset} phx-change="validate" phx-submit="save" class="space-y-4">
        <div class="form-control">
          <label class="label"><span class="label-text">Name</span></label>
          <input
            type="text"
            name="knowledge_base[name]"
            value={Ecto.Changeset.get_field(@changeset, :name)}
            class="input input-bordered w-full"
            required
          />
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text">Description</span></label>
          <textarea
            name="knowledge_base[description]"
            class="textarea textarea-bordered w-full"
            rows="3"
          >{Ecto.Changeset.get_field(@changeset, :description)}</textarea>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div class="form-control">
            <label class="label"><span class="label-text">Type</span></label>
            <select name="knowledge_base[type]" class="select select-bordered w-full">
              <option
                value="documents"
                selected={Ecto.Changeset.get_field(@changeset, :type) == :documents}
              >
                Documents
              </option>
              <option
                value="web_crawl"
                selected={Ecto.Changeset.get_field(@changeset, :type) == :web_crawl}
              >
                Web Crawl
              </option>
              <option
                value="database"
                selected={Ecto.Changeset.get_field(@changeset, :type) == :database}
              >
                Database
              </option>
              <option
                value="api"
                selected={Ecto.Changeset.get_field(@changeset, :type) == :api}
              >
                API
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text">Chunking Strategy</span></label>
            <select name="knowledge_base[chunk_strategy]" class="select select-bordered w-full">
              <option
                value="fixed"
                selected={Ecto.Changeset.get_field(@changeset, :chunk_strategy) == :fixed}
              >
                Fixed Size
              </option>
              <option
                value="paragraph"
                selected={Ecto.Changeset.get_field(@changeset, :chunk_strategy) == :paragraph}
              >
                Paragraph
              </option>
              <option
                value="semantic"
                selected={Ecto.Changeset.get_field(@changeset, :chunk_strategy) == :semantic}
              >
                Semantic
              </option>
            </select>
          </div>
        </div>

        <div class="grid grid-cols-3 gap-4">
          <div class="form-control">
            <label class="label"><span class="label-text">Chunk Size</span></label>
            <input
              type="number"
              name="knowledge_base[chunk_size]"
              value={Ecto.Changeset.get_field(@changeset, :chunk_size)}
              class="input input-bordered w-full"
              min="1"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text">Chunk Overlap</span></label>
            <input
              type="number"
              name="knowledge_base[chunk_overlap]"
              value={Ecto.Changeset.get_field(@changeset, :chunk_overlap)}
              class="input input-bordered w-full"
              min="0"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text">Embedding Model</span></label>
            <input
              type="text"
              name="knowledge_base[embedding_model]"
              value={Ecto.Changeset.get_field(@changeset, :embedding_model)}
              class="input input-bordered w-full"
            />
          </div>
        </div>

        <div class="flex gap-2">
          <button type="submit" class="btn btn-primary">
            {if @action == :new, do: "Create Codex", else: "Save Changes"}
          </button>
          <.link
            navigate={
              ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/knowledge-bases"
            }
            class="btn btn-ghost"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end
end
