defmodule Summoner.Adapters.Persistence.MediaFixtures do
  @moduledoc """
  Test helpers for creating media-related entities.
  """

  alias Summoner.Adapters.Persistence.Media

  def valid_media_attachment_attributes(workspace_id, conversation_id, attrs \\ %{}) do
    Enum.into(attrs, %{
      workspace_id: workspace_id,
      conversation_id: conversation_id,
      source: :uploaded,
      type: :image,
      filename: "test_image_#{System.unique_integer([:positive])}.png",
      content_type: "image/png",
      metadata: %{}
    })
  end

  def media_attachment_fixture(workspace_id, conversation_id, attrs \\ %{}) do
    attrs = valid_media_attachment_attributes(workspace_id, conversation_id, attrs)

    {:ok, attachment} = Media.create_uploaded_attachment(attrs)
    attachment
  end

  def pending_attachment_fixture(workspace_id, conversation_id, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        workspace_id: workspace_id,
        conversation_id: conversation_id,
        source: :generated,
        type: :image,
        filename: "generated_#{System.unique_integer([:positive])}.png",
        content_type: "image/png",
        prompt: "A test image",
        metadata: %{}
      })

    {:ok, attachment} = Media.create_pending_attachment(attrs)
    attachment
  end

  @doc """
  Creates a 1x1 red pixel PNG for testing file storage.
  """
  def tiny_png do
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44,
      0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90,
      0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8,
      0xCF, 0xC0, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33, 0x00, 0x00, 0x00,
      0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82>>
  end
end
