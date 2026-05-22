defmodule Summoner.Ports.DocumentParser.Adapter do
  @moduledoc "Behaviour for document parsing operations."

  @type parse_result :: {:ok, %{text: String.t(), metadata: map()}} | {:error, String.t()}

  @callback parse(binary(), String.t()) :: parse_result()
  @callback supported_types() :: [String.t()]
end
