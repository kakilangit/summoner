defmodule SummonerWeb.AccessTokenLive.Form do
  use SummonerWeb, :live_view

  alias Summoner.Domain.Policies.WorkspacePolicy
  alias Summoner.Domain.Schemas.AccessToken
  alias Summoner.Ports.Persistence.AccessTokens

  @impl true
  def mount(params, _session, socket) do
    workspace = socket.assigns.workspace

    if WorkspacePolicy.can?(socket.assigns.membership, :operate) do
      {token, title, editing} =
        case params["id"] do
          nil ->
            {%AccessToken{
               workspace_id: workspace.id,
               tenant_id: workspace.tenant_id,
               scopes: [],
               rate_limit_rpm: 100
             }, "New Ward", false}

          id ->
            {AccessTokens.get_token!(workspace.id, id), "Edit Ward", true}
        end

      changeset = token_changeset(token, %{})

      socket =
        socket
        |> assign(
          page_title: "#{title} - #{workspace.name}",
          token: token,
          form: to_form(changeset, as: "token"),
          title: title,
          editing: editing,
          new_plaintext: nil,
          breadcrumbs: [
            {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
            {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
            {"Wards",
             ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/access-tokens"},
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
  def handle_event("validate", %{"token" => params}, socket) do
    changeset =
      token_changeset(socket.assigns.token, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "token"))}
  end

  @impl true
  def handle_event("save", %{"token" => params}, socket) do
    params = ensure_scopes(params)

    if socket.assigns.editing do
      update_token(socket, params)
    else
      create_token(socket, params)
    end
  end

  defp create_token(socket, params) do
    workspace = socket.assigns.workspace

    attrs =
      params |> Map.put("workspace_id", workspace.id) |> Map.put("tenant_id", workspace.tenant_id)

    case AccessTokens.create_token(attrs) do
      {:ok, token} ->
        {:noreply,
         socket
         |> assign(new_plaintext: token.token)
         |> put_flash(:info, "Ward created. Copy the token now — it won't be shown again.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "token"))}
    end
  end

  defp update_token(socket, params) do
    workspace = socket.assigns.workspace

    case AccessTokens.update_token(socket.assigns.token, params) do
      {:ok, _token} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ward updated.")
         |> push_navigate(
           to:
             ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/access-tokens/#{socket.assigns.token.id}"
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "token"))}
    end
  end

  defp ensure_scopes(%{"scopes" => scopes} = params) when is_list(scopes), do: params
  defp ensure_scopes(params), do: Map.put(params, "scopes", [])

  defp token_changeset(token, params) do
    if token.id do
      AccessToken.update_changeset(token, params)
    else
      AccessToken.create_changeset(token, params)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <h1 class="text-2xl font-bold">{@title}</h1>

      <div :if={@new_plaintext} class="alert alert-success text-sm" role="alert">
        <div class="flex-1">
          <p class="font-medium">Copy now — shown once:</p>
          <code class="font-mono select-all break-all">{@new_plaintext}</code>
        </div>
        <.link
          navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/access-tokens"}
          class="btn btn-xs btn-ghost"
        >
          Done
        </.link>
      </div>

      <.form
        :if={@new_plaintext == nil}
        for={@form}
        id="token-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input field={@form[:label]} type="text" label="Label" placeholder="My API token" required />

        <div class="form-control">
          <label class="label">
            <span class="label-text">Scopes</span>
          </label>
          <div class="flex flex-wrap gap-3">
            <label
              :for={scope <- ~w(a2a api admin webhook)}
              class="label cursor-pointer gap-2"
            >
              <input
                type="checkbox"
                name="token[scopes][]"
                value={scope}
                class="checkbox checkbox-sm"
                checked={scope in (@form[:scopes].value || [])}
              />
              <span class="label-text uppercase text-sm">{scope}</span>
            </label>
          </div>
          <p
            :for={{msg, _} <- @form[:scopes].errors || []}
            class="text-xs text-error mt-1"
          >
            {msg}
          </p>
        </div>

        <.input
          field={@form[:rate_limit_rpm]}
          type="number"
          label="Rate limit (requests/min)"
          placeholder="100"
          min="1"
          max="10000"
        />
        <p class="text-xs text-base-content/50 -mt-2">
          Maximum requests per minute. Default: 100.
        </p>

        <.input field={@form[:expires_at]} type="datetime-local" label="Expires at (optional)" />
        <p class="text-xs text-base-content/50 -mt-2">
          Leave empty for a token that never expires. Must be in the future.
        </p>

        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/access-tokens"}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </.link>
          <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
            {if @editing, do: "Update Ward", else: "Create Ward"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end
end
