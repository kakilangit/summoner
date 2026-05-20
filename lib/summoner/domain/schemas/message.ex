defmodule Summoner.Domain.Schemas.Message do
  @moduledoc """
  Schema for Messages within a conversation.

  Messages represent the chat history: user inputs, assistant responses,
  system notifications, and tool result messages. Orchestration and
  lifecycle events live in `invocation_events`, not here.

  ## Roles

  - `user` — human input
  - `assistant` — Agent response
  - `system` — system-generated (e.g., handoff notices)
  - `tool` — LLM-formatted tool result fed back into context

  ## Visibility

  - `public` — visible in the main chat UI
  - `internal` — hidden from the user; used for worker outputs,
    pipeline stages, and orchestration summaries

  ## Kind

  - `chat` — normal conversational message
  - `summary` — condensed context summary
  - `generate_image — user prompt for image generation (media mode)
  - `generate_video — user prompt for video generation (media mode)
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.Conversation
  alias Summoner.Domain.Types.Content

  @roles ~w(user assistant system tool)a
  @visibilities ~w(public internal)a
  @kinds ~w(chat summary generate_image generate_video)a

  schema "messages" do
    field :role, Ecto.Enum, values: @roles
    field :visibility, Ecto.Enum, values: @visibilities, default: :public
    field :kind, Ecto.Enum, values: @kinds, default: :chat
    field :content, {:array, :map}, default: []
    field :tool_call_id, :string
    field :tool_calls, {:array, :map}
    field :token_count, :integer
    field :deleted_at, :utc_datetime_usec
    field :compacted_at, :utc_datetime_usec
    field :thinking, :string
    field :provider_name, :string
    field :model_name, :string

    belongs_to :conversation, Conversation
    # invocation_id is a forward reference — the invocations schema
    # will be defined in Phase 1.8. We store the raw NULID here.
    field :invocation_id, Nulid.Ecto
    belongs_to :agent, Agent

    timestamps(updated_at: false)
  end

  @required_fields ~w(conversation_id role)a
  @optional_fields ~w(invocation_id agent_id visibility kind content thinking tool_call_id tool_calls token_count provider_name model_name)a

  def changeset(message, attrs) do
    message
    |> cast(normalize_content(attrs), @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:visibility, @visibilities)
    |> validate_inclusion(:kind, @kinds)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:invocation_id)
    |> foreign_key_constraint(:agent_id)
  end

  defp normalize_content(%{content: content} = attrs) when is_binary(content) do
    Map.put(attrs, :content, Content.from_string(content))
  end

  defp normalize_content(%{"content" => content} = attrs) when is_binary(content) do
    Map.put(attrs, "content", Content.from_string(content))
  end

  defp normalize_content(attrs), do: attrs
end
