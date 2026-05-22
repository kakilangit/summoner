defmodule Summoner.Services.Orchestration.CompositeToolExecutor do
  @moduledoc """
  Composite `ToolExecutor` that dispatches to built-in tools first,
  then falls back to MCP tool execution.

  Built-in tools (`bash`, `read`, `write`, `edit`, `grep`, `glob`)
  are always available and execute within the workspace sandbox.
  Media tools (`__generate_image__`) enqueue Oban jobs for async generation.
  MCP tools are namespaced as `"server__tool"` and routed to
  `McpToolExecutor`.
  """

  @behaviour Summoner.Services.Orchestration.ToolExecutor

  alias Summoner.Ports.Persistence.AgentMemories
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Artifacts
  alias Summoner.Ports.Persistence.Media
  alias Summoner.Ports.Persistence.MediaProviders
  alias Summoner.Ports.Persistence.Workspaces
  alias Summoner.Ports.Workers
  alias Summoner.Services.Embedding
  alias Summoner.Services.Memory.PartySharing
  alias Summoner.Services.Orchestration.{BuiltinTools, McpToolExecutor}

  @impl true
  def execute(tool_call, %{agent_id: _agent_id, workspace_id: workspace_id} = context) do
    tool_name = tool_call.function.name

    cond do
      tool_name == "__generate_image__" ->
        execute_generate_image(tool_call, context)

      tool_name == "__generate_video__" ->
        execute_generate_video(tool_call, context)

      tool_name in ~w(__create_artifact__ __update_artifact__ __read_artifact__) ->
        execute_artifact_tool(tool_name, tool_call, context)

      tool_name == "__remember__" ->
        execute_remember(tool_call, context)

      BuiltinTools.builtin?(tool_name) ->
        execute_builtin(tool_call, workspace_id)

      true ->
        McpToolExecutor.execute(tool_call, context)
    end
  end

  defp execute_builtin(tool_call, workspace_id) do
    workspace_root = Workspaces.workspace_dir(workspace_id)

    with {:ok, args} <- parse_arguments(tool_call.function.arguments) do
      BuiltinTools.execute(tool_call.function.name, args, workspace_root)
    end
  end

  defp execute_generate_image(tool_call, context) do
    with {:ok, args} <- parse_arguments(tool_call.function.arguments) do
      agent = Agents.get_agent_with_provider!(context.agent_id)

      case MediaProviders.resolve_media_provider(agent, :image) do
        nil ->
          {:error,
           "No media provider is configured for image generation in this workspace. " <>
             "Set up a Forge in workspace settings first."}

        media_provider ->
          {:ok, attachment} =
            Media.create_pending_attachment(%{
              workspace_id: context.workspace_id,
              conversation_id: context.conversation_id,
              source: :generated,
              type: :image,
              filename: "generated_#{System.unique_integer([:positive])}.png",
              content_type: "image/png",
              prompt: args["prompt"],
              model_name: media_provider.default_image_model,
              provider_name: media_provider.name,
              metadata: %{}
            })

          Workers.enqueue_media_generation(%{
            "attachment_id" => attachment.id,
            "media_provider_id" => media_provider.id,
            "type" => "image",
            "params" => args
          })

          {:ok,
           "Image generation started (ID: #{attachment.id}). " <>
             "It will appear in the conversation when ready."}
      end
    end
  end

  defp execute_generate_video(tool_call, context) do
    with {:ok, args} <- parse_arguments(tool_call.function.arguments) do
      agent = Agents.get_agent_with_provider!(context.agent_id)

      case MediaProviders.resolve_media_provider(agent, :video) do
        nil ->
          {:error,
           "No media provider is configured for video generation in this workspace. " <>
             "Set up a Forge with a video model in workspace settings first."}

        media_provider ->
          {:ok, attachment} =
            Media.create_pending_attachment(%{
              workspace_id: context.workspace_id,
              conversation_id: context.conversation_id,
              source: :generated,
              type: :video,
              filename: "generated_#{System.unique_integer([:positive])}.mp4",
              content_type: "video/mp4",
              prompt: args["prompt"],
              model_name: media_provider.default_video_model,
              provider_name: media_provider.name,
              metadata: %{}
            })

          Workers.enqueue_media_generation(%{
            "attachment_id" => attachment.id,
            "media_provider_id" => media_provider.id,
            "type" => "video",
            "params" => args
          })

          {:ok,
           "Video generation started (ID: #{attachment.id}). " <>
             "It will appear in the conversation when ready (may take several minutes)."}
      end
    end
  end

  defp execute_artifact_tool(action, tool_call, context)
       when action in ~w(__create_artifact__ __update_artifact__) do
    with {:ok, args} <- parse_arguments(tool_call.function.arguments) do
      existing = lookup_artifact(context[:conversation_id], args["name"])
      attrs = build_artifact_attrs(args, existing, context)
      upsert_artifact(attrs, existing)
    end
  end

  defp execute_artifact_tool("__read_artifact__", tool_call, context) do
    with {:ok, args} <- parse_arguments(tool_call.function.arguments) do
      case lookup_artifact(context[:conversation_id], args["name"]) do
        nil -> {:error, "Artifact '#{args["name"]}' not found."}
        a -> {:ok, "# #{a.name} (v#{a.version}, #{a.type})\n\n#{a.content || ""}"}
      end
    end
  end

  defp upsert_artifact(attrs, existing) do
    case Artifacts.create_artifact(%{user: nil}, attrs) do
      {:ok, artifact} ->
        verb = if existing, do: "updated to", else: "created"
        {:ok, "Artifact '#{artifact.name}' #{verb} v#{artifact.version} (ID: #{artifact.id})."}

      {:error, changeset} ->
        {:error, "Failed to create artifact: #{inspect(changeset.errors)}"}
    end
  end

  defp lookup_artifact(nil, _name), do: nil

  defp lookup_artifact(conversation_id, name),
    do: Artifacts.get_artifact_by_name(conversation_id, name)

  defp build_artifact_attrs(args, existing, context) do
    base = %{
      name: args["name"],
      type: args["type"] || (existing && existing.type) || "document",
      content: args["content"],
      content_type:
        args["content_type"] || (existing && existing.content_type) || "text/markdown",
      workspace_id: context.workspace_id,
      agent_id: context.agent_id,
      conversation_id: context[:conversation_id]
    }

    if existing do
      Map.merge(base, %{version: existing.version + 1, parent_id: existing.id})
    else
      base
    end
  end

  defp execute_remember(tool_call, context) do
    with {:ok, args} <- parse_arguments(tool_call.function.arguments),
         {:ok, attrs} <- build_memory_attrs(args, context),
         attrs = maybe_embed_memory(attrs, context.workspace_id),
         {:ok, memory} <- AgentMemories.create_memory(attrs) do
      Task.start(fn -> PartySharing.share_memory(memory) end)
      {:ok, "Remembered #{memory.type}: #{String.slice(memory.content, 0..50)}..."}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Failed to store memory: #{inspect(changeset.errors)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @memory_types %{
    "fact" => :fact,
    "preference" => :preference,
    "procedure" => :procedure,
    "correction" => :correction
  }

  defp build_memory_attrs(args, context) do
    case Map.fetch(@memory_types, args["type"]) do
      {:ok, type} ->
        {:ok,
         %{
           content: args["content"],
           type: type,
           agent_id: context.agent_id,
           workspace_id: context.workspace_id,
           source_conversation_id: context[:conversation_id]
         }}

      :error ->
        {:error,
         "Invalid memory type: #{inspect(args["type"])}. Must be one of: fact, preference, procedure, correction"}
    end
  end

  defp maybe_embed_memory(attrs, workspace_id) do
    case Embedding.embed(workspace_id, attrs.content) do
      {:ok, vector} -> Map.put(attrs, :embedding, vector)
      _ -> attrs
    end
  end

  defp parse_arguments(""), do: {:ok, %{}}

  defp parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, "invalid tool arguments JSON: #{args}"}
    end
  end

  defp parse_arguments(args) when is_map(args), do: {:ok, args}
  defp parse_arguments(_), do: {:ok, %{}}
end
