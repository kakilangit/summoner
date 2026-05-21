defmodule SummonerWeb.API.V1.ConversationController do
  @moduledoc "REST API controller for conversations (Channels)."

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.Conversations
  alias SummonerWeb.API.Schemas

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  tags ["conversations"]

  operation :index,
    summary: "List conversations",
    parameters: [
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"Conversation list", "application/json", Schemas.ConversationListResponse}]

  operation :show,
    summary: "Get conversation",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Conversation", "application/json", Schemas.ConversationResponse}]

  operation :create,
    summary: "Create conversation",
    request_body: {"Conversation params", "application/json", Schemas.ConversationParams},
    responses: [
      created: {"Conversation", "application/json", Schemas.ConversationResponse},
      unprocessable_entity: {"Validation error", "application/json", Schemas.ErrorResponse}
    ]

  operation :delete,
    summary: "Delete conversation",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Deleted"]

  operation :messages,
    summary: "List conversation messages",
    parameters: [
      conversation_id: [in: :path, type: :string, required: true],
      page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false],
      per_page: [in: :query, schema: %OpenApiSpex.Schema{type: :integer}, required: false]
    ],
    responses: [ok: {"Message list", "application/json", Schemas.MessageListResponse}]

  operation :export,
    summary: "Export conversation as markdown",
    parameters: [conversation_id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Markdown export", "text/markdown", %OpenApiSpex.Schema{type: :string}}]

  def index(conn, params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id

    page =
      Conversations.list_conversations_paginated(scope, workspace_id, pagination_opts(params))

    render(conn, :index, page: page)
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

    page = Conversations.list_messages_paginated(conversation_id, pagination_opts(params))
    render(conn, :messages, page: page)
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
