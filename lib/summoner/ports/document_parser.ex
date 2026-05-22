defmodule Summoner.Ports.DocumentParser do
  @moduledoc "Port for document parsing operations."

  @adapter Application.compile_env(
             :summoner,
             [:adapters, :document_parser],
             Summoner.Adapters.RAG.DocumentParser
           )

  defdelegate parse(binary, content_type), to: @adapter
  defdelegate supported_types(), to: @adapter
end
