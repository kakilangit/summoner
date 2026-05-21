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

  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Artifacts
  alias Summoner.Ports.Persistence.Media
  alias Summoner.Ports.Persistence.MediaProviders
  alias Summoner.Ports.Persistence.Workspaces
  alias Summoner.Ports.Workers
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

  defp execute_artifact_tool("__create_artifact__", tool_call, context) do
    with {:ok, args} <- parse_arguments(tool_call.function.arguments) do
      attrs = %{
        name: args["name"],
        type: args["type"],
        content: args["content"],
        content_type: args["content_type"] || "text/markdown",
        workspace_id: context.workspace_id,
        agent_id: context.agent_id,
        conversation_id: context[:conversation_id]
      }

      scope = %{user: nil}

      case Artifacts.create_artifact(scope, attrs) do
        {:ok, artifact} ->
          {:ok, "Artifact '#{artifact.name}' created (v#{artifact.version}, ID: #{artifact.id})."}

        {:error, changeset} ->
          {:error, "Failed to create artifact: #{inspect(changeset.errors)}"}
      end
    end
  end

  defp execute_artifact_tool("__update_artifact__", tool_call, context) do
    with {:ok, args} <- parse_arguments(tool_call.function.arguments),
         existing when not is_nil(existing) <-
           Artifacts.get_artifact_by_name(context.workspace_id, args["name"]) do
      attrs = %{
        name: existing.name,
        type: existing.type,
        content: args["content"],
        content_type: existing.content_type,
        version: existing.version + 1,
        parent_id: existing.id,
        workspace_id: context.workspace_id,
        agent_id: context.agent_id,
        conversation_id: context[:conversation_id]
      }

      case Artifacts.create_artifact(%{user: nil}, attrs) do
        {:ok, artifact} ->
          {:ok,
           "Artifact '#{artifact.name}' updated to v#{artifact.version} (ID: #{artifact.id})."}

        {:error, changeset} ->
          {:error, "Failed to update artifact: #{inspect(changeset.errors)}"}
      end
    else
      nil -> {:error, "Artifact not found."}
      error -> error
    end
  end

  defp execute_artifact_tool("__read_artifact__", tool_call, context) do
    with {:ok, args} <- parse_arguments(tool_call.function.arguments) do
      case Artifacts.get_artifact_by_name(context.workspace_id, args["name"]) do
        nil ->
          {:error, "Artifact '#{args["name"]}' not found."}

        artifact ->
          {:ok,
           "# #{artifact.name} (v#{artifact.version}, #{artifact.type})\n\n#{artifact.content || ""}"}
      end
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
