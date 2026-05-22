defmodule SummonerWeb.KnowledgeBaseLive.Show do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Ports.Persistence.KnowledgeBases
  alias Summoner.Ports.Persistence.KnowledgeChunks
  alias Summoner.Services.Embedding
  alias Summoner.Services.RAG

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workspace = socket.assigns.workspace
    kb = KnowledgeBases.get_knowledge_base!(workspace.id, id)
    linked_agents = KnowledgeBases.list_linked_agents(kb.id)
    chunk_count = KnowledgeChunks.count_by_knowledge_base(kb.id)

    socket =
      socket
      |> assign(
        page_title: "#{kb.name} - Codex",
        kb: kb,
        linked_agents: linked_agents,
        chunk_count: chunk_count,
        search_query: "",
        search_results: nil
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Codex",
           ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/knowledge-bases"},
          {kb.name, nil}
        ]
      )
      |> allow_upload(:document,
        accept: ~w(.txt .md .html .pdf .docx),
        max_file_size: 50_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("upload", _params, socket) do
    authorize(socket, :configure, fn ->
      workspace = socket.assigns.workspace
      kb = socket.assigns.kb

      consumed =
        consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
          process_upload(kb, workspace, path, entry)
        end)

      flash = upload_flash(consumed)
      kb = KnowledgeBases.get_knowledge_base!(workspace.id, kb.id)

      {:noreply, socket |> assign(kb: kb) |> put_flash(:info, flash)}
    end)
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("reindex_all", _params, socket) do
    authorize(socket, :configure, fn ->
      workspace = socket.assigns.workspace
      kb = socket.assigns.kb

      case RAG.reindex_all(workspace.id, kb.id) do
        {:ok, _job} ->
          {:noreply, put_flash(socket, :info, "Re-indexing queued.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Re-index failed: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def handle_event("delete_document", %{"filename" => filename}, socket) do
    authorize(socket, :configure, fn ->
      kb = socket.assigns.kb

      KnowledgeChunks.delete_by_document(kb.id, filename)

      new_hashes = Map.delete(kb.file_hashes || %{}, filename)
      new_count = max((kb.document_count || 1) - 1, 0)

      case KnowledgeBases.update_status(kb, %{
             file_hashes: new_hashes,
             document_count: new_count
           }) do
        {:ok, kb} ->
          chunk_count = KnowledgeChunks.count_by_knowledge_base(kb.id)

          {:noreply,
           socket
           |> assign(kb: kb, chunk_count: chunk_count)
           |> put_flash(:info, "Document \"#{filename}\" removed.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Delete failed: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def handle_event("unlink_agent", %{"agent-id" => agent_id}, socket) do
    authorize(socket, :configure, fn ->
      kb = socket.assigns.kb

      case KnowledgeBases.unlink_agent(kb.id, agent_id) do
        {:ok, _} ->
          linked_agents = KnowledgeBases.list_linked_agents(kb.id)

          {:noreply,
           socket |> assign(linked_agents: linked_agents) |> put_flash(:info, "Agent unlinked.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Unlink failed: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    kb = socket.assigns.kb
    workspace = socket.assigns.workspace

    if String.trim(query) == "" do
      {:noreply, assign(socket, search_results: nil, search_query: "")}
    else
      # Search using cosine similarity on this KB's chunks directly
      case Embedding.embed(workspace.id, query) do
        {:ok, embedding} ->
          results =
            KnowledgeChunks.cosine_search([kb.id], embedding, limit: 10, threshold: 0.5)

          {:noreply, assign(socket, search_results: results, search_query: query)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(search_query: query)
           |> put_flash(:error, "Search failed: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    authorize(socket, :configure, fn ->
      workspace = socket.assigns.workspace
      kb = socket.assigns.kb

      case KnowledgeBases.delete_knowledge_base(kb) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Codex deleted.")
           |> push_navigate(
             to: ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/knowledge-bases"
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Delete failed: #{inspect(reason)}")}
      end
    end)
  end

  defp process_upload(kb, workspace, path, entry) do
    filename = entry.client_name
    binary = File.read!(path)

    case RAG.check_document_change(kb, filename, binary) do
      :unchanged ->
        {:ok, {:skipped, filename}}

      _ ->
        case RAG.ingest_document(workspace.id, kb.id, filename, entry.client_type) do
          {:ok, _job} -> {:ok, {:ingested, filename}}
          {:error, reason} -> {:ok, {:error, filename, reason}}
        end
    end
  end

  defp upload_flash(consumed) do
    ingested = Enum.count(consumed, &match?({:ingested, _}, &1))
    skipped = Enum.count(consumed, &match?({:skipped, _}, &1))

    cond do
      ingested > 0 && skipped > 0 ->
        "#{ingested} document(s) queued for ingestion, #{skipped} unchanged."

      ingested > 0 ->
        "#{ingested} document(s) queued for ingestion."

      skipped > 0 ->
        "All documents unchanged."

      true ->
        "No documents uploaded."
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">{@kb.name}</h1>
          <p :if={@kb.description} class="text-sm text-base-content/60 mt-1">{@kb.description}</p>
        </div>
        <div :if={@can?.(:configure)} class="flex gap-2">
          <.link
            navigate={
              ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/knowledge-bases/#{@kb.id}/edit"
            }
            class="btn btn-ghost btn-sm"
          >
            Edit
          </.link>
          <button
            phx-click={show_confirm("#delete-kb")}
            class="btn btn-error btn-sm btn-outline"
          >
            Delete
          </button>
          <.confirm_modal
            id="delete-kb"
            title="Delete codex?"
            message={"#{@kb.name} and all its documents will be permanently removed."}
            confirm_text="Delete"
            on_confirm={JS.push("delete")}
          />
        </div>
      </div>

      <%!-- Status & Info --%>
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h2 class="card-title text-lg">Info</h2>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
            <div>
              <span class="text-base-content/60">Type</span>
              <p class="font-medium">{@kb.type}</p>
            </div>
            <div>
              <span class="text-base-content/60">Status</span>
              <p>
                <span class={["badge badge-sm", status_badge_class(@kb.status)]}>
                  {@kb.status}
                </span>
              </p>
              <p :if={@kb.error_message} class="text-xs text-error mt-1">{@kb.error_message}</p>
            </div>
            <div>
              <span class="text-base-content/60">Documents</span>
              <p class="font-medium">{@kb.document_count}</p>
            </div>
            <div>
              <span class="text-base-content/60">Chunks</span>
              <p class="font-medium">{@chunk_count}</p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Configuration --%>
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h2 class="card-title text-lg">Configuration</h2>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
            <div>
              <span class="text-base-content/60">Embedding Model</span>
              <p class="font-medium">{@kb.embedding_model}</p>
            </div>
            <div>
              <span class="text-base-content/60">Chunk Strategy</span>
              <p class="font-medium">{@kb.chunk_strategy}</p>
            </div>
            <div>
              <span class="text-base-content/60">Chunk Size</span>
              <p class="font-medium">{@kb.chunk_size}</p>
            </div>
            <div>
              <span class="text-base-content/60">Chunk Overlap</span>
              <p class="font-medium">{@kb.chunk_overlap}</p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Documents --%>
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <div class="flex items-center justify-between">
            <h2 class="card-title text-lg">Documents</h2>
            <div :if={@can?.(:configure)} class="flex gap-2">
              <button phx-click="reindex_all" class="btn btn-ghost btn-sm">
                Re-index All
              </button>
            </div>
          </div>

          <div
            :if={@kb.file_hashes == %{} or @kb.file_hashes == nil}
            class="py-4 text-center text-base-content/60"
          >
            No documents uploaded yet.
          </div>

          <div :if={@kb.file_hashes != %{} and @kb.file_hashes != nil} class="space-y-2 mt-2">
            <div
              :for={{filename, hash} <- @kb.file_hashes}
              class="flex items-center justify-between p-3 bg-base-300 rounded-lg"
            >
              <div class="min-w-0 flex-1">
                <p class="font-medium truncate">{filename}</p>
                <p class="text-xs text-base-content/50 font-mono">{String.slice(hash, 0..15)}...</p>
              </div>
              <button
                :if={@can?.(:configure)}
                phx-click="delete_document"
                phx-value-filename={filename}
                class="btn btn-error btn-xs btn-outline flex-shrink-0"
              >
                Delete
              </button>
            </div>
          </div>

          <div :if={@can?.(:configure)} class="mt-4">
            <form phx-change="validate_upload" phx-submit="upload" class="flex items-end gap-2">
              <div class="form-control flex-1">
                <label class="label"><span class="label-text">Upload Documents</span></label>
                <.live_file_input
                  upload={@uploads.document}
                  class="file-input file-input-bordered w-full"
                />
              </div>
              <button type="submit" class="btn btn-primary btn-sm">Upload</button>
            </form>
          </div>
        </div>
      </div>

      <%!-- Linked Agents --%>
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h2 class="card-title text-lg">Linked Agents</h2>

          <div :if={@linked_agents == []} class="py-4 text-center text-base-content/60">
            No agents linked. Link agents from the agent detail page.
          </div>

          <div :if={@linked_agents != []} class="space-y-2 mt-2">
            <div
              :for={agent <- @linked_agents}
              class="flex items-center justify-between p-3 bg-base-300 rounded-lg"
            >
              <.link
                navigate={
                  ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/agents/#{agent.id}"
                }
                class="font-medium hover:underline"
              >
                {agent.name}
              </.link>
              <button
                :if={@can?.(:configure)}
                phx-click="unlink_agent"
                phx-value-agent-id={agent.id}
                class="btn btn-warning btn-xs btn-outline"
              >
                Unlink
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Search Testing --%>
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h2 class="card-title text-lg">Search Test</h2>
          <form phx-submit="search" class="flex gap-2">
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Enter a query to test retrieval..."
              class="input input-bordered flex-1"
            />
            <button type="submit" class="btn btn-primary btn-sm">Search</button>
          </form>

          <div :if={@search_results != nil} class="mt-4 space-y-3">
            <p :if={@search_results == []} class="text-base-content/60">
              No results found for "{@search_query}".
            </p>

            <div
              :for={chunk <- @search_results}
              class="p-3 bg-base-300 rounded-lg"
            >
              <div class="flex items-center justify-between mb-1">
                <span class="text-xs font-medium text-base-content/60">
                  {chunk.document_name}
                </span>
                <span class="badge badge-sm badge-info">
                  {Float.round(chunk.similarity, 3)}
                </span>
              </div>
              <p class="text-sm whitespace-pre-wrap">{chunk.content}</p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge_class(:ready), do: "badge-success"
  defp status_badge_class(:indexing), do: "badge-info"
  defp status_badge_class(:error), do: "badge-error"
  defp status_badge_class(_), do: "badge-warning"
end
