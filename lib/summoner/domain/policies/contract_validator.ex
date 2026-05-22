defmodule Summoner.Domain.Policies.ContractValidator do
  @moduledoc """
  Pure policy for validating plugin capability contracts.

  On enable, each declared capability is tested. Returns
  `{:ok, results}` or `{:error, failures}`.
  """

  @doc """
  Validates that the given capability responses satisfy the contract.

  Returns `:ok` or `{:error, reason}`.
  """
  def validate_tools(tool_list, expected_tools) do
    tool_names = Enum.map(tool_list, & &1["name"])
    missing = expected_tools -- tool_names

    if missing == [] do
      :ok
    else
      {:error, "Missing expected tools: #{Enum.join(missing, ", ")}"}
    end
  end

  def validate_webhook_response(response) do
    case response do
      %{"actions" => actions} when is_list(actions) -> :ok
      _ -> {:error, "Webhook response must include an 'actions' array"}
    end
  end

  def validate_hook_response(response) do
    case response do
      %{"action" => action} when action in ["proceed", "modify", "halt"] -> :ok
      _ -> {:error, "Hook response must include 'action' (proceed|modify|halt)"}
    end
  end

  def validate_models_response(response) do
    case response do
      models when is_list(models) ->
        if Enum.all?(models, &valid_model?/1) do
          :ok
        else
          {:error, "Each model must have 'id' and 'name' fields"}
        end

      _ ->
        {:error, "Models response must be a list"}
    end
  end

  defp valid_model?(%{"id" => _, "name" => _}), do: true
  defp valid_model?(_), do: false
end
