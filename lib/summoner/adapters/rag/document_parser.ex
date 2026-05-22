defmodule Summoner.Adapters.RAG.DocumentParser do
  @moduledoc """
  Document parser adapter.

  Dispatches to format-specific parsers based on content type.
  Supports plain text, markdown, HTML, PDF (via pdftotext CLI),
  and DOCX (via zip XML extraction).
  """

  @behaviour Summoner.Ports.DocumentParser.Adapter

  @supported_types ~w(
    text/plain
    text/markdown
    text/html
    application/pdf
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
  )

  @impl true
  def supported_types, do: @supported_types

  @impl true
  def parse(binary, content_type) do
    case content_type do
      "text/plain" ->
        parse_text(binary)

      "text/markdown" ->
        parse_markdown(binary)

      "text/html" ->
        parse_html(binary)

      "application/pdf" ->
        parse_pdf(binary)

      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ->
        parse_docx(binary)

      _ ->
        {:error, "unsupported content type: #{content_type}"}
    end
  end

  defp parse_text(binary) do
    text = to_string(binary)
    {:ok, %{text: text, metadata: %{}}}
  end

  defp parse_markdown(binary) do
    text = to_string(binary)

    # Strip markdown formatting to get plain text, preserving structure
    plain =
      text
      # headers
      |> String.replace(~r/^[#]{1,6}\s+/m, "")
      # bold
      |> String.replace(~r/\*\*(.+?)\*\*/, "\\1")
      # italic
      |> String.replace(~r/\*(.+?)\*/, "\\1")
      # inline code
      |> String.replace(~r/`(.+?)`/, "\\1")
      # code blocks
      |> String.replace(~r/```[\s\S]*?```/, "")
      # links
      |> String.replace(~r/\[([^\]]+)\]\([^\)]+\)/, "\\1")
      # list markers
      |> String.replace(~r/^[-*+]\s+/m, "")
      # numbered lists
      |> String.replace(~r/^\d+\.\s+/m, "")
      |> String.trim()

    # Extract headings for metadata
    headings =
      ~r/^([#]{1,6})\s+(.+)$/m
      |> Regex.scan(text)
      |> Enum.map(fn [_, hashes, title] ->
        %{level: String.length(hashes), title: String.trim(title)}
      end)

    {:ok, %{text: plain, metadata: %{headings: headings}}}
  end

  defp parse_html(binary) do
    plain =
      binary
      |> to_string()
      |> String.replace(~r/<script[^>]*>[\s\S]*?<\/script>/i, "")
      |> String.replace(~r/<style[^>]*>[\s\S]*?<\/style>/i, "")
      |> String.replace(~r/<[^>]+>/, " ")
      |> String.replace(~r/&nbsp;/, " ")
      |> String.replace(~r/&amp;/, "&")
      |> String.replace(~r/&lt;/, "<")
      |> String.replace(~r/&gt;/, ">")
      |> String.replace(~r/&quot;/, "\"")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    {:ok, %{text: plain, metadata: %{}}}
  end

  defp parse_pdf(binary) do
    tmp_dir = System.tmp_dir!()
    id = :erlang.unique_integer([:positive])
    input_path = Path.join(tmp_dir, "summoner_pdf_#{id}.pdf")
    output_path = input_path <> ".txt"

    try do
      File.write!(input_path, binary)

      case System.cmd("pdftotext", ["-layout", input_path, output_path], stderr_to_stdout: true) do
        {_, 0} ->
          text = File.read!(output_path)
          pages = String.split(text, "\f")
          page_count = length(pages)

          {:ok, %{text: String.trim(text), metadata: %{page_count: page_count}}}

        {error, _} ->
          {:error, "pdftotext failed: #{error}"}
      end
    after
      File.rm(input_path)
      File.rm(output_path)
    end
  end

  defp parse_docx(binary) do
    case :zip.unzip(binary, [:memory]) do
      {:ok, files} ->
        case Enum.find(files, fn {name, _} ->
               to_string(name) == "word/document.xml"
             end) do
          {_, xml_binary} ->
            text =
              xml_binary
              |> to_string()
              # paragraph breaks
              |> String.replace(~r/<w:p[^>]*>/, "\n")
              |> String.replace(~r/<w:tab\/>/, "\t")
              # strip all XML tags
              |> String.replace(~r/<[^>]+>/, "")
              |> String.replace(~r/\n{3,}/, "\n\n")
              |> String.trim()

            {:ok, %{text: text, metadata: %{}}}

          nil ->
            {:error, "no document.xml found in DOCX archive"}
        end

      {:error, reason} ->
        {:error, "failed to unzip DOCX: #{inspect(reason)}"}
    end
  end
end
