defmodule Summoner.Domain.Policies.InputTransform do
  @moduledoc """
  Pure input transformation for webhook payloads.

  Applies a simple template interpolation to transform raw webhook
  body params into structured agent input. Templates use `\#{$.path.to.field}`
  syntax to extract values from the incoming JSON payload.
  """

  @doc """
  Apply a transform template to body params.

  Returns the body params unchanged if no transform is configured.
  """
  @spec apply_transform(map(), String.t() | nil) :: map()
  def apply_transform(body_params, nil), do: body_params
  def apply_transform(body_params, ""), do: body_params

  def apply_transform(body_params, template) do
    message = interpolate(template, body_params)
    Map.put(body_params, "message", message)
  end

  @doc "Interpolate `\#{$.path}` references in a template string."
  @spec interpolate(String.t(), map()) :: String.t()
  def interpolate(template, data) do
    Regex.replace(~r/#\{\$\.([^}]+)\}/, template, fn _match, path ->
      resolve_path(data, String.split(path, ".")) |> to_string()
    end)
  end

  defp resolve_path(data, []), do: data

  defp resolve_path(data, [key | rest]) when is_map(data) do
    case Map.get(data, key) do
      nil -> ""
      value -> resolve_path(value, rest)
    end
  end

  defp resolve_path(_data, _path), do: ""
end
