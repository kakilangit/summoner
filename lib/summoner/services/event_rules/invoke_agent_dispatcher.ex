defmodule Summoner.Services.EventRules.InvokeAgentDispatcher do
  @moduledoc """
  Action dispatcher that invokes an agent when an event rule fires.

  Supports targeting by `agent_id` or `agent_callname`. Optionally
  interpolates the event payload into the input message via a template.
  """

  @behaviour Summoner.Services.EventRules.ActionDispatcher

  alias Summoner.Ports.Persistence.Agents

  require Logger

  @impl true
  def dispatch(action_config, event_data) do
    workspace_id = event_data["workspace_id"]

    with {:ok, agent} <- resolve_agent(action_config, workspace_id),
         message <- build_message(action_config, event_data),
         params <- %{message: message, conversation_id: nil} do
      case Agents.execute_sync(agent, workspace_id, params) do
        {:ok, invocation} ->
          {:ok, %{invocation_id: invocation.id, agent_id: agent.id}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp resolve_agent(%{"agent_id" => agent_id}, workspace_id)
       when is_binary(agent_id) and is_binary(workspace_id) do
    scope = %{user: :system}

    try do
      {:ok, Agents.get_agent!(scope, workspace_id, agent_id)}
    rescue
      Ecto.NoResultsError -> {:error, :agent_not_found}
    end
  end

  defp resolve_agent(%{"agent_callname" => callname}, workspace_id)
       when is_binary(callname) and is_binary(workspace_id) do
    scope = %{user: :system}

    case Agents.get_agent_by_callname(scope, workspace_id, callname) do
      nil -> {:error, :agent_not_found}
      agent -> {:ok, agent}
    end
  end

  defp resolve_agent(_config, _workspace_id), do: {:error, :no_agent_specified}

  defp build_message(%{"input_template" => template}, event_data) when is_binary(template) do
    interpolate(template, event_data)
  end

  defp build_message(_config, event_data) do
    "Event rule triggered.\n\nEvent data:\n```json\n#{Jason.encode!(event_data, pretty: true)}\n```"
  end

  @doc false
  def interpolate(template, data) do
    Regex.replace(~r/\{\{([^}]+)\}\}/, template, fn _full, path ->
      path
      |> String.trim()
      |> String.split(".")
      |> get_nested(data)
      |> to_string()
    end)
  end

  defp get_nested([], value), do: value
  defp get_nested(_keys, nil), do: ""

  defp get_nested([key | rest], %{} = data) do
    value = Map.get(data, key) || Map.get(data, String.to_existing_atom(key))
    get_nested(rest, value)
  rescue
    ArgumentError -> ""
  end

  defp get_nested(_keys, _data), do: ""
end
