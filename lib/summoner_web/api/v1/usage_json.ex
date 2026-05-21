defmodule SummonerWeb.API.V1.UsageJSON do
  @moduledoc "JSON rendering for usage analytics."

  def index(%{usage: usage}) do
    usage
  end

  def breakdowns(%{breakdowns: breakdowns}) do
    %{
      by_agent: Enum.map(breakdowns.by_agent, &breakdown_entry/1),
      by_model: Enum.map(breakdowns.by_model, &breakdown_entry/1),
      by_provider: Enum.map(breakdowns.by_provider, &breakdown_entry/1)
    }
  end

  defp breakdown_entry(entry) do
    Map.take(entry, [
      :agent_id,
      :model,
      :provider_id,
      :total_tokens,
      :prompt_tokens,
      :completion_tokens,
      :invocation_count
    ])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
