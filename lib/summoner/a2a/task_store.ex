defmodule Summoner.A2A.TaskStore do
  @moduledoc """
  Postgres-backed implementation of `A2A.TaskStore`.

  Persists `A2A.Task` structs as serialized JSON in the `a2a_tasks` table.
  The store reference is an `a2a_server_id` (NULID string) used to scope
  tasks to a specific Herald.
  """

  @behaviour A2A.TaskStore

  import Ecto.Query, warn: false

  alias Summoner.A2A.A2ATask
  alias Summoner.Repo

  alias A2A.FileContent
  alias A2A.Part
  alias A2A.Task.Filter, as: TaskFilter
  alias A2A.Task.Status, as: TaskStatus

  @impl A2A.TaskStore
  def get(server_id, task_id) do
    case Repo.get_by(A2ATask, id: task_id, a2a_server_id: server_id) do
      nil -> {:error, :not_found}
      record -> {:ok, deserialize(record)}
    end
  end

  @impl A2A.TaskStore
  def put(server_id, %A2A.Task{} = task) do
    serialized = serialize(task)

    case Repo.get(A2ATask, task.id) do
      nil ->
        %A2ATask{}
        |> A2ATask.changeset(%{
          id: task.id,
          direction: :inbound,
          context_id: task.context_id,
          state: task.status.state,
          metadata: task.metadata |> Map.delete(:stream),
          task_data: serialized,
          a2a_server_id: server_id
        })
        |> Repo.insert()

      record ->
        record
        |> A2ATask.changeset(%{
          state: task.status.state,
          context_id: task.context_id,
          metadata: task.metadata |> Map.delete(:stream),
          task_data: serialized
        })
        |> Repo.update()
    end
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl A2A.TaskStore
  def delete(server_id, task_id) do
    case Repo.get_by(A2ATask, id: task_id, a2a_server_id: server_id) do
      nil -> :ok
      record -> Repo.delete(record) |> elem(0) |> then(fn :ok -> :ok end)
    end
  end

  @impl A2A.TaskStore
  def list(server_id, context_id) do
    tasks =
      A2ATask
      |> where(a2a_server_id: ^server_id, context_id: ^context_id)
      |> order_by([t], asc: t.inserted_at)
      |> Repo.all()
      |> Enum.map(&deserialize/1)

    {:ok, tasks}
  end

  @impl A2A.TaskStore
  def list_all(server_id, opts \\ []) do
    A2ATask
    |> where(a2a_server_id: ^server_id)
    |> apply_filters(opts)
    |> order_by([t], desc: t.inserted_at)
    |> apply_pagination(opts)
    |> Repo.all()
    |> Enum.map(&deserialize/1)
    |> TaskFilter.apply(opts)
  end

  # -------------------------------------------------------------------
  # Serialization
  # -------------------------------------------------------------------

  defp serialize(%A2A.Task{} = task) do
    task
    |> A2A.Task.strip_stream_metadata()
    |> encode_task()
  end

  defp encode_task(task) do
    %{
      "id" => task.id,
      "contextId" => task.context_id,
      "status" => encode_status(task.status),
      "history" => Enum.map(task.history, &encode_message/1),
      "artifacts" => Enum.map(task.artifacts, &encode_artifact/1),
      "metadata" => task.metadata
    }
  end

  defp encode_status(%TaskStatus{} = status) do
    map = %{"state" => to_string(status.state)}

    map =
      if status.message, do: Map.put(map, "message", encode_message(status.message)), else: map

    if status.timestamp,
      do: Map.put(map, "timestamp", DateTime.to_iso8601(status.timestamp)),
      else: map
  end

  defp encode_message(%A2A.Message{} = msg) do
    %{
      "messageId" => msg.message_id,
      "role" => to_string(msg.role),
      "parts" => Enum.map(msg.parts, &encode_part/1),
      "metadata" => msg.metadata
    }
  end

  defp encode_part(%A2A.Part.Text{} = part) do
    %{"kind" => "text", "text" => part.text, "metadata" => part.metadata}
  end

  defp encode_part(%A2A.Part.File{} = part) do
    file = %{}
    file = if part.file.uri, do: Map.put(file, "uri", part.file.uri), else: file
    file = if part.file.bytes, do: Map.put(file, "bytes", part.file.bytes), else: file
    file = if part.file.name, do: Map.put(file, "name", part.file.name), else: file
    file = if part.file.mime_type, do: Map.put(file, "mimeType", part.file.mime_type), else: file
    %{"kind" => "file", "file" => file, "metadata" => part.metadata}
  end

  defp encode_part(%A2A.Part.Data{} = part) do
    %{"kind" => "data", "data" => part.data, "metadata" => part.metadata}
  end

  defp encode_artifact(%A2A.Artifact{} = artifact) do
    %{
      "artifactId" => artifact.artifact_id,
      "name" => artifact.name,
      "description" => artifact.description,
      "parts" => Enum.map(artifact.parts, &encode_part/1),
      "metadata" => artifact.metadata
    }
  end

  # -------------------------------------------------------------------
  # Deserialization
  # -------------------------------------------------------------------

  defp deserialize(%A2ATask{task_data: nil, id: id, state: state}) do
    %A2A.Task{
      id: id,
      status: TaskStatus.new(state)
    }
  end

  defp deserialize(%A2ATask{task_data: data}) when is_map(data) do
    decode_task(data)
  end

  defp decode_task(data) do
    %A2A.Task{
      id: data["id"],
      context_id: data["contextId"],
      status: decode_status(data["status"] || %{}),
      history: Enum.map(data["history"] || [], &decode_message/1),
      artifacts: Enum.map(data["artifacts"] || [], &decode_artifact/1),
      metadata: data["metadata"] || %{}
    }
  end

  defp decode_status(data) do
    state = String.to_existing_atom(data["state"] || "submitted")
    message = if data["message"], do: decode_message(data["message"])

    timestamp =
      case data["timestamp"] do
        nil -> nil
        ts -> DateTime.from_iso8601(ts) |> elem(1)
      end

    %TaskStatus{state: state, message: message, timestamp: timestamp}
  end

  defp decode_message(data) do
    %A2A.Message{
      message_id: data["messageId"] || A2A.ID.generate("msg"),
      role: String.to_existing_atom(data["role"] || "user"),
      parts: Enum.map(data["parts"] || [], &decode_part/1),
      metadata: data["metadata"] || %{}
    }
  end

  defp decode_part(%{"kind" => "text"} = data) do
    Part.Text.new(data["text"], data["metadata"] || %{})
  end

  defp decode_part(%{"kind" => "file"} = data) do
    file_data = data["file"] || %{}

    file = %FileContent{
      uri: file_data["uri"],
      bytes: file_data["bytes"],
      name: file_data["name"],
      mime_type: file_data["mimeType"]
    }

    Part.File.new(file, data["metadata"] || %{})
  end

  defp decode_part(%{"kind" => "data"} = data) do
    Part.Data.new(data["data"] || %{}, data["metadata"] || %{})
  end

  defp decode_part(_data), do: Part.Text.new("")

  defp decode_artifact(data) do
    %A2A.Artifact{
      artifact_id: data["artifactId"] || A2A.ID.generate("art"),
      name: data["name"],
      description: data["description"],
      parts: Enum.map(data["parts"] || [], &decode_part/1),
      metadata: data["metadata"] || %{}
    }
  end

  # -------------------------------------------------------------------
  # Query Helpers
  # -------------------------------------------------------------------

  defp apply_filters(query, opts) do
    query
    |> maybe_filter_context(opts[:context_id])
    |> maybe_filter_state(opts[:status])
  end

  defp maybe_filter_context(query, nil), do: query
  defp maybe_filter_context(query, ctx), do: where(query, context_id: ^ctx)

  defp maybe_filter_state(query, nil), do: query
  defp maybe_filter_state(query, state), do: where(query, state: ^state)

  defp apply_pagination(query, opts) do
    limit = opts[:page_size] || 50
    limit(query, ^limit)
  end
end
