defmodule SummonerWeb.WardLive.Index do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.A2A, as: SummonerA2A

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Wards - #{workspace.name}",
        new_token: nil,
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Wards", nil}
        ]
      )
      |> load_tokens()

    {:ok, socket}
  end

  @impl true
  def handle_event("create_token", %{"label" => label}, socket) do
    authorize(socket, :operate, fn ->
      case SummonerA2A.create_token(%{
             workspace_id: socket.assigns.workspace.id,
             label: label
           }) do
        {:ok, token} ->
          {:noreply,
           socket
           |> assign(new_token: token.token)
           |> load_tokens()
           |> put_flash(:info, "Token created. Copy it now — it won't be shown again.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to create token.")}
      end
    end)
  end

  def handle_event("dismiss_token", _params, socket) do
    {:noreply, assign(socket, new_token: nil)}
  end

  def handle_event("revoke", %{"id" => token_id}, socket) do
    authorize(socket, :operate, fn ->
      token = Enum.find(socket.assigns.tokens, &(&1.id == token_id))

      if token do
        {:ok, _} = SummonerA2A.revoke_token(token)

        {:noreply,
         socket
         |> load_tokens()
         |> put_flash(:info, "Token revoked.")}
      else
        {:noreply, socket}
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Wards</h1>
          <p class="text-sm text-base-content/60">
            Access tokens for protected Heralds in this realm.
          </p>
        </div>
        <form :if={@can?.(:operate)} phx-submit="create_token" class="flex items-end gap-2">
          <input
            type="text"
            name="label"
            placeholder="Token label"
            required
            class="input input-sm w-40"
          />
          <button type="submit" class="btn btn-primary btn-sm">Create</button>
        </form>
      </div>

      <div :if={@new_token} class="alert alert-success text-sm" role="alert">
        <div class="flex-1">
          <p class="font-medium">Copy now — shown once:</p>
          <code class="font-mono select-all break-all">{@new_token}</code>
        </div>
        <button phx-click="dismiss_token" class="btn btn-xs btn-ghost">OK</button>
      </div>

      <div :if={@tokens == []} class="text-center py-12 text-base-content/60">
        <p>No tokens yet. Create one to authenticate external A2A clients.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={token <- @tokens}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="min-w-0 flex-1">
            <span class="font-medium">{token.label}</span>
            <div class="text-sm text-base-content/60">
              {token.request_count} requests {if token.last_used_at,
                do: " · #{format_relative(token.last_used_at)}",
                else: " · never used"}
            </div>
          </div>
          <div :if={@can?.(:operate)} class="flex-shrink-0">
            <button
              phx-click={show_confirm("#revoke-token-#{token.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Revoke
            </button>
            <.confirm_modal
              id={"revoke-token-#{token.id}"}
              title="Revoke token?"
              message="External clients using this token will lose access immediately."
              confirm_text="Revoke"
              on_confirm={JS.push("revoke", value: %{id: token.id})}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp load_tokens(socket) do
    tokens = SummonerA2A.list_tokens(socket.assigns.workspace.id)
    assign(socket, tokens: tokens)
  end

  defp format_relative(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end
