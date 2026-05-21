defmodule SummonerWeb.AccessTokenLive.Show do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Domain.Schemas.AccessToken
  alias Summoner.Ports.Persistence.AccessTokens

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workspace = socket.assigns.workspace
    token = AccessTokens.get_token!(workspace.id, id)

    socket =
      socket
      |> assign(
        page_title: "#{token.label} - #{workspace.name}",
        token: token,
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Wards", ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/access-tokens"},
          {token.label, nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("revoke", _params, socket) do
    authorize(socket, :operate, fn ->
      {:ok, _} = AccessTokens.revoke_token(socket.assigns.token)
      workspace = socket.assigns.workspace

      {:noreply,
       socket
       |> put_flash(:info, "Token revoked.")
       |> push_navigate(
         to: ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/access-tokens"
       )}
    end)
  end

  @impl true
  def handle_event("delete", _params, socket) do
    authorize(socket, :operate, fn ->
      workspace = socket.assigns.workspace

      case AccessTokens.delete_token(socket.assigns.token) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Token deleted.")
           |> push_navigate(
             to: ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/access-tokens"
           )}

        {:error, :not_revoked} ->
          {:noreply, put_flash(socket, :error, "Token must be revoked before deleting.")}
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">{@token.label}</h1>
        <div :if={@can?.(:operate)} class="flex gap-2">
          <.link
            :if={is_nil(@token.revoked_at)}
            navigate={
              ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/access-tokens/#{@token.id}/edit"
            }
            class="btn btn-primary btn-sm"
          >
            Edit
          </.link>
          <button
            :if={is_nil(@token.revoked_at)}
            phx-click={show_confirm("#revoke-token")}
            class="btn btn-error btn-sm btn-outline"
          >
            Revoke
          </button>
          <button
            :if={not is_nil(@token.revoked_at)}
            phx-click={show_confirm("#delete-token")}
            class="btn btn-error btn-sm btn-outline"
          >
            Delete
          </button>
          <.confirm_modal
            id="revoke-token"
            title="Revoke token?"
            message="External clients using this token will lose access immediately. This cannot be undone."
            confirm_text="Revoke"
            on_confirm={JS.push("revoke")}
          />
          <.confirm_modal
            id="delete-token"
            title="Delete token?"
            message="This will permanently remove the token. This cannot be undone."
            confirm_text="Delete"
            on_confirm={JS.push("delete")}
          />
        </div>
      </div>

      <.status_badge token={@token} />

      <div class="bg-base-200 rounded-box p-4 space-y-3">
        <div class="grid grid-cols-[auto,1fr] gap-x-4 gap-y-2 text-sm">
          <div class="text-base-content/60">Scopes</div>
          <div class="flex flex-wrap gap-1">
            <span :for={scope <- @token.scopes} class="badge badge-sm badge-outline uppercase">
              {scope}
            </span>
            <span :if={@token.scopes == []} class="text-base-content/40">none</span>
          </div>

          <div class="text-base-content/60">Rate limit</div>
          <div>{@token.rate_limit_rpm} req/min</div>

          <div class="text-base-content/60">Requests</div>
          <div>{@token.request_count}</div>

          <div class="text-base-content/60">Last used</div>
          <div>
            {if @token.last_used_at, do: format_datetime(@token.last_used_at), else: "never"}
          </div>

          <div class="text-base-content/60">Expires</div>
          <div>
            {if @token.expires_at, do: format_datetime(@token.expires_at), else: "never"}
          </div>

          <div :if={@token.revoked_at} class="text-base-content/60">Revoked</div>
          <div :if={@token.revoked_at}>{format_datetime(@token.revoked_at)}</div>

          <div class="text-base-content/60">Created</div>
          <div>{format_datetime(@token.inserted_at)}</div>
        </div>
      </div>
    </div>
    """
  end

  attr :token, AccessToken, required: true

  defp status_badge(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span :if={@token.revoked_at} class="badge badge-error badge-sm">revoked</span>
      <span
        :if={is_nil(@token.revoked_at) and AccessToken.active?(@token)}
        class="badge badge-success badge-sm"
      >
        active
      </span>
      <span
        :if={is_nil(@token.revoked_at) and not AccessToken.active?(@token)}
        class="badge badge-warning badge-sm"
      >
        expired
      </span>
    </div>
    """
  end

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end
end
