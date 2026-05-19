defmodule Summoner.Domain.Types.ContentVisionTest do
  use Summoner.DataCase

  alias Summoner.Adapters.Persistence.Media
  alias Summoner.Domain.Types.Content

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.ConversationsFixtures
  import Summoner.Adapters.Persistence.MediaFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup do
    user = user_fixture()
    scope = %Summoner.Domain.Schemas.Scope{user: user}
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)
    conversation = conversation_fixture(scope, workspace.id, agent.id)

    on_exit(fn ->
      upload_dir = Path.join("priv/static/uploads", workspace.id)
      File.rm_rf(upload_dir)
    end)

    %{workspace: workspace, conversation: conversation}
  end

  describe "to_intent_blocks/2 with attachments map" do
    test "resolves image attachment to base64 block", ctx do
      att = media_attachment_fixture(ctx.workspace.id, ctx.conversation.id)
      binary = tiny_png()
      :ok = Media.store_file(att, binary)

      blocks = [
        %{"type" => "text", "text" => "Look at this:"},
        %{"type" => "image", "media_attachment_id" => att.id, "alt" => "test image"}
      ]

      att_map = %{att.id => Media.get_attachment!(att.id)}
      result = Content.to_intent_blocks(blocks, att_map)

      assert [
               %{type: :text, text: "Look at this:"},
               %{type: :image_base64, media_type: "image/png", data: data}
             ] = result

      assert is_binary(data)
      assert Base.decode64!(data) == binary
    end

    test "falls back to text placeholder when attachment not in map", _ctx do
      blocks = [
        %{"type" => "image", "media_attachment_id" => "nonexistent", "alt" => "missing"}
      ]

      result = Content.to_intent_blocks(blocks, %{})
      assert [%{type: :text, text: "[Image: missing]"}] = result
    end

    test "falls back to text placeholder for pending attachment", ctx do
      att = pending_attachment_fixture(ctx.workspace.id, ctx.conversation.id)

      blocks = [
        %{"type" => "image", "media_attachment_id" => att.id, "alt" => "pending"}
      ]

      att_map = %{att.id => att}
      result = Content.to_intent_blocks(blocks, att_map)

      assert [%{type: :text, text: "[Image: pending]"}] = result
    end

    test "without attachments map, falls back to text", _ctx do
      blocks = [
        %{"type" => "image", "media_attachment_id" => "some_id", "alt" => "no map"}
      ]

      result = Content.to_intent_blocks(blocks)
      assert [%{type: :text, text: "[Image: no map]"}] = result
    end

    test "video blocks always become text placeholders", _ctx do
      blocks = [
        %{"type" => "video", "media_attachment_id" => "vid_id", "alt" => "demo clip"}
      ]

      result = Content.to_intent_blocks(blocks, %{})
      assert [%{type: :text, text: "[Video: demo clip]"}] = result
    end
  end
end
