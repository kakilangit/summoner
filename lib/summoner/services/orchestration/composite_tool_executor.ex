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
