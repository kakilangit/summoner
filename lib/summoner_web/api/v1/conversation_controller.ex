defmodule SummonerWeb.API.V1.ConversationController do
  @moduledoc "REST API controller for conversations (Channels)."

  use SummonerWeb, :controller

  alias Summoner.Ports.Persistence.Conversations

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  def index(conn, _params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    conversations = Conversations.list_conversations(scope, workspace_id)
    render(conn, :index, conversations: conversations)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    conversation = Conversations.get_conversation!(scope, workspace_id, id)
    render(conn, :show, conversation: conversation)
  end

  def create(conn, %{"conversation" => attrs}) do
    scope = conn.assigns.current_scope
    attrs = Map.put(attrs, "workspace_id", conn.assigns.current_workspace_id)

    case Conversations.create_conversation(scope, attrs) do
      {:ok, conversation} ->
        conn
        |> put_status(:created)
        |> render(:show, conversation: conversation)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    conversation = Conversations.get_conversation!(scope, workspace_id, id)

    with {:ok, _} <- Conversations.delete_conversation(scope, conversation) do
      send_resp(conn, :no_content, "")
    end
  end

  def messages(conn, %{"conversation_id" => conversation_id} = params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id

    # Verify conversation belongs to workspace
    _conversation = Conversations.get_conversation!(scope, workspace_id, conversation_id)

    opts = []

    opts =
      if params["limit"], do: [{:limit, String.to_integer(params["limit"])} | opts], else: opts

    messages = Conversations.list_messages(conversation_id, opts)
    render(conn, :messages, messages: messages)
  end

  def export(conn, %{"conversation_id" => conversation_id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    _conversation = Conversations.get_conversation!(scope, workspace_id, conversation_id)

    markdown = Conversations.export_as_markdown(conversation_id)

    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, markdown)
  end
end
