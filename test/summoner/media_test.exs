defmodule Summoner.MediaTest do
  use Summoner.DataCase

  alias Summoner.Media

  import Summoner.AccountsFixtures
  import Summoner.AgentsFixtures
  import Summoner.ConversationsFixtures
  import Summoner.MediaFixtures
  import Summoner.ProvidersFixtures
  import Summoner.WorkspacesFixtures

  setup do
    user = user_fixture()
    scope = %Summoner.Accounts.Scope{user: user}
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)
    conversation = conversation_fixture(scope, workspace.id, agent.id)

    on_exit(fn ->
      # Clean up any test upload files
      upload_dir = Path.join("priv/static/uploads", workspace.id)
      File.rm_rf(upload_dir)
    end)

    %{workspace: workspace, conversation: conversation, scope: scope}
  end

  describe "create_uploaded_attachment/1" do
    test "creates a ready attachment for uploaded file", ctx do
      {:ok, attachment} =
        Media.create_uploaded_attachment(%{
          workspace_id: ctx.workspace.id,
          conversation_id: ctx.conversation.id,
          type: :image,
          filename: "photo.jpg",
          content_type: "image/jpeg",
          file_size: 12_345,
          metadata: %{}
        })

      assert attachment.source == :uploaded
      assert attachment.status == :ready
      assert attachment.type == :image
      assert attachment.filename == "photo.jpg"
      assert attachment.content_type == "image/jpeg"
      assert attachment.file_size == 12_345
    end
  end

  describe "create_pending_attachment/1" do
    test "creates a pending attachment for generation", ctx do
      {:ok, attachment} =
        Media.create_pending_attachment(%{
          workspace_id: ctx.workspace.id,
          conversation_id: ctx.conversation.id,
          source: :generated,
          type: :image,
          filename: "generated.png",
          content_type: "image/png",
          prompt: "A mystical castle",
          metadata: %{}
        })

      assert attachment.status == :pending
      assert attachment.source == :generated
      assert attachment.prompt == "A mystical castle"
    end
  end

  describe "lifecycle" do
    test "mark_ready/2 transitions pending to ready", ctx do
      att = pending_attachment_fixture(ctx.workspace.id, ctx.conversation.id)
      assert att.status == :pending

      {:ok, ready} = Media.mark_ready(att, %{file_size: 1024, width: 512, height: 512})
      assert ready.status == :ready
      assert ready.file_size == 1024
      assert ready.width == 512
    end

    test "mark_failed/2 transitions to failed with reason", ctx do
      att = pending_attachment_fixture(ctx.workspace.id, ctx.conversation.id)

      {:ok, failed} = Media.mark_failed(att, "Provider returned 429")
      assert failed.status == :failed
      assert failed.error == "Provider returned 429"
    end
  end

  describe "file storage" do
    test "store_file/2 and read_file/1 round-trip", ctx do
      att = media_attachment_fixture(ctx.workspace.id, ctx.conversation.id)
      binary = tiny_png()

      assert :ok = Media.store_file(att, binary)
      assert {:ok, ^binary} = Media.read_file(att)
    end

    test "delete_file/1 removes file from disk", ctx do
      att = media_attachment_fixture(ctx.workspace.id, ctx.conversation.id)
      :ok = Media.store_file(att, tiny_png())

      assert :ok = Media.delete_file(att)
      assert {:error, :enoent} = Media.read_file(att)
    end

    test "delete_file/1 is idempotent for missing files", ctx do
      att = media_attachment_fixture(ctx.workspace.id, ctx.conversation.id)
      assert :ok = Media.delete_file(att)
    end

    test "media_url/1 returns correct URL path", ctx do
      att = media_attachment_fixture(ctx.workspace.id, ctx.conversation.id)
      url = Media.media_url(att)
      assert url =~ "/uploads/#{ctx.workspace.id}/#{att.id}.png"
    end
  end

  describe "queries" do
    test "get_attachment!/1 retrieves by ID", ctx do
      att = media_attachment_fixture(ctx.workspace.id, ctx.conversation.id)
      found = Media.get_attachment!(att.id)
      assert found.id == att.id
    end

    test "list_conversation_attachments/1", ctx do
      att1 = media_attachment_fixture(ctx.workspace.id, ctx.conversation.id)
      att2 = media_attachment_fixture(ctx.workspace.id, ctx.conversation.id)

      attachments = Media.list_conversation_attachments(ctx.conversation.id)
      ids = Enum.map(attachments, & &1.id)
      assert att1.id in ids
      assert att2.id in ids
    end

    test "list_workspace_attachments/2 with filters", ctx do
      _img = media_attachment_fixture(ctx.workspace.id, ctx.conversation.id, %{type: :image})

      _vid =
        media_attachment_fixture(ctx.workspace.id, ctx.conversation.id, %{
          type: :video,
          filename: "vid.mp4",
          content_type: "video/mp4"
        })

      images = Media.list_workspace_attachments(ctx.workspace.id, type: :image)
      assert length(images) == 1
      assert hd(images).type == :image

      videos = Media.list_workspace_attachments(ctx.workspace.id, type: :video)
      assert length(videos) == 1
      assert hd(videos).type == :video
    end

    test "get_attachments_map/1 returns map of id => attachment", ctx do
      att1 = media_attachment_fixture(ctx.workspace.id, ctx.conversation.id)
      att2 = media_attachment_fixture(ctx.workspace.id, ctx.conversation.id)

      map = Media.get_attachments_map([att1.id, att2.id])
      assert map[att1.id].id == att1.id
      assert map[att2.id].id == att2.id
    end

    test "workspace_storage_used/1 sums ready file sizes", ctx do
      media_attachment_fixture(ctx.workspace.id, ctx.conversation.id, %{file_size: 1000})
      media_attachment_fixture(ctx.workspace.id, ctx.conversation.id, %{file_size: 2000})

      assert Media.workspace_storage_used(ctx.workspace.id) == 3000
    end
  end

  describe "validation" do
    test "validate_file_size/2" do
      assert Media.validate_file_size(:image, 1_000_000)
      refute Media.validate_file_size(:image, 20_000_000)
      assert Media.validate_file_size(:video, 50_000_000)
      refute Media.validate_file_size(:video, 200_000_000)
    end
  end
end
