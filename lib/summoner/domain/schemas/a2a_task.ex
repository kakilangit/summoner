defmodule Summoner.Domain.Schemas.A2ATask do
  @moduledoc """
  Schema for A2A task tracking — unified for inbound and outbound.

  Inbound tasks (from external clients via Herald) set `a2a_server_id`.
  Outbound tasks (to remote agents via Envoy) set `agent_id`.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.A2AServer
  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.Conversation

  @directions ~w(inbound outbound)a
  @states ~w(submitted working completed failed canceled input_required)a

  schema "a2a_tasks" do
    field :direction, Ecto.Enum, values: @directions
    field :context_id, :string
    field :state, Ecto.Enum, values: @states, default: :submitted
    field :metadata, :map, default: %{}
    field :task_data, :map
    field :remote_client_info, :map

    belongs_to :a2a_server, A2AServer
    belongs_to :agent, Agent
    belongs_to :conversation, Conversation

    timestamps()
  end

  @cast_fields [
    :direction,
    :context_id,
    :state,
    :metadata,
    :task_data,
    :remote_client_info,
    :a2a_server_id,
    :agent_id,
    :conversation_id
  ]

  @required_fields [:direction]

  @doc """
  Changeset for creating or updating an A2A task.
  """
  def changeset(task, attrs) do
    task
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:direction, @directions)
    |> validate_inclusion(:state, @states)
    |> foreign_key_constraint(:a2a_server_id)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:conversation_id)
  end
end
