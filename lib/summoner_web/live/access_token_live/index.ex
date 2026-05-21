defmodule SummonerWeb.AccessTokenLive.Index do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Domain.Schemas.AccessToken
  alias Summoner.Ports.Persistence.AccessTokens

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Wards - #{workspace.name}",
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Wards", nil}
        ]
      )
      |> load_tokens()

    {:ok, socket}
  end

  @impl true
  def handle_event("revoke", %{"id" => token_id}, socket) do
    authorize(socket, :operate, fn ->
      token = Enum.find(socket.assigns.tokens, &(&1.id == token_id))

      if token do
        {:ok, _} = AccessTokens.revoke_token(token)

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
  def handle_event("delete", %{"id" => token_id}, socket) do
    authorize(socket, :operate, fn ->
      token = Enum.find(socket.assigns.tokens, &(&1.id == token_id))

      case token && AccessTokens.delete_token(token) do
        {:ok, _} ->
          {:noreply,
           socket
           |> load_tokens()
           |> put_flash(:info, "Token deleted.")}

        {:error, :not_revoked} ->
          {:noreply, put_flash(socket, :error, "Token must be revoked before deleting.")}

        _ ->
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
            Manage scoped access tokens for A2A, API, webhooks, OpenAI-compat, and MCP.
          </p>
        </div>
        <.link
          :if={@can?.(:operate)}
          navigate={
            ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/access-tokens/new"
          }
          class="btn btn-primary btn-sm"
        >
          New Ward
        </.link>
      </div>

      <div :if={@tokens == []} class="text-center py-12 text-base-content/60">
        <p>No tokens yet. Create one to authenticate external clients.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={token <- @tokens}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <.link
                navigate={
                  ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/access-tokens/#{token.id}"
                }
                class="font-medium hover:underline truncate"
              >
                {token.label}
              </.link>
              <.token_status token={token} />
            </div>
            <div class="flex gap-1 mt-1">
              <span :for={scope <- token.scopes} class="badge badge-xs badge-outline uppercase">
                {scope}
              </span>
            </div>
            <div class="text-sm text-base-content/60">
              {token.request_count} requests {if token.last_used_at,
                do: " · #{format_relative(token.last_used_at)}",
                else: " · never used"}
              {if token.expires_at, do: " · expires #{format_relative(token.expires_at)}"}
            </div>
          </div>
          <div :if={@can?.(:operate)} class="flex gap-2 flex-shrink-0">
            <button
              :if={is_nil(token.revoked_at)}
              phx-click={show_confirm("#revoke-token-#{token.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Revoke
            </button>
            <button
              :if={not is_nil(token.revoked_at)}
              phx-click={show_confirm("#delete-token-#{token.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Delete
            </button>
            <.confirm_modal
              :if={is_nil(token.revoked_at)}
              id={"revoke-token-#{token.id}"}
              title="Revoke token?"
              message="External clients using this token will lose access immediately."
              confirm_text="Revoke"
              on_confirm={JS.push("revoke", value: %{id: token.id})}
            />
            <.confirm_modal
              :if={not is_nil(token.revoked_at)}
              id={"delete-token-#{token.id}"}
              title="Delete token?"
              message="This will permanently remove the token. This cannot be undone."
              confirm_text="Delete"
              on_confirm={JS.push("delete", value: %{id: token.id})}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :token, AccessToken, required: true

  defp token_status(assigns) do
    ~H"""
    <span :if={@token.revoked_at} class="badge badge-error badge-xs">revoked</span>
    <span
      :if={is_nil(@token.revoked_at) and AccessToken.active?(@token)}
      class="badge badge-success badge-xs"
    >
      active
    </span>
    <span
      :if={is_nil(@token.revoked_at) and not AccessToken.active?(@token)}
      class="badge badge-warning badge-xs"
    >
      expired
    </span>
    """
  end

  defp load_tokens(socket) do
    tokens = AccessTokens.list_tokens(socket.assigns.workspace.id, include_revoked: true)
    assign(socket, tokens: tokens)
  end

  defp format_relative(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 0 -> "in #{format_relative_abs(-diff)}"
      diff < 60 -> "just now"
      true -> "#{format_relative_abs(diff)} ago"
    end
  end

  defp format_relative_abs(diff) do
    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86_400 -> "#{div(diff, 3600)}h"
      true -> "#{div(diff, 86_400)}d"
    end
  end
end
