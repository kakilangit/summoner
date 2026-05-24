defmodule Summoner.Domain.Policies.ManifestValidator do
  @moduledoc """
  Pure validation of plugin manifests (grimoire.json).

  Validates required fields and capability-specific configuration.
  No side effects — returns `{:ok, manifest}` or `{:error, reasons}`.
  """

  alias Summoner.Domain.Schemas.PluginInstallation

  @required_fields ~w(name version image capabilities)
  @optional_fields ~w(summoner description webhooks events hooks provider theme config_schema network resources)

  @doc "Validates a parsed manifest map. Returns `{:ok, manifest}` or `{:error, [String.t()]}`."
  def validate(manifest) when is_map(manifest) do
    errors =
      []
      |> validate_required_fields(manifest)
      |> validate_capabilities(manifest)
      |> validate_capability_configs(manifest)

    case errors do
      [] -> {:ok, manifest}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  def validate(_), do: {:error, ["manifest must be a map"]}

  defp validate_required_fields(errors, manifest) do
    Enum.reduce(@required_fields, errors, fn field, acc ->
      if Map.has_key?(manifest, field) do
        acc
      else
        ["missing required field: #{field}" | acc]
      end
    end)
  end

  defp validate_capabilities(errors, manifest) do
    case manifest["capabilities"] do
      caps when is_list(caps) and caps != [] ->
        valid = PluginInstallation.valid_capabilities()
        invalid = Enum.reject(caps, &(&1 in valid))

        if invalid == [] do
          errors
        else
          ["invalid capabilities: #{Enum.join(invalid, ", ")}" | errors]
        end

      [] ->
        ["capabilities must not be empty" | errors]

      _ ->
        errors
    end
  end

  defp validate_capability_configs(errors, manifest) do
    caps = manifest["capabilities"] || []

    errors
    |> maybe_validate_webhooks(caps, manifest)
    |> maybe_validate_events(caps, manifest)
    |> maybe_validate_hooks(caps, manifest)
    |> maybe_validate_provider(caps, manifest)
  end

  defp maybe_validate_webhooks(errors, caps, manifest) do
    if "webhooks" in caps do
      case manifest["webhooks"] do
        %{"routes" => routes} when is_list(routes) and routes != [] -> errors
        nil -> ["webhooks capability requires webhooks.routes" | errors]
        _ -> ["webhooks.routes must be a non-empty list" | errors]
      end
    else
      errors
    end
  end

  defp maybe_validate_events(errors, caps, manifest) do
    if "events" in caps do
      case manifest["events"] do
        %{"subscribes" => subs} when is_list(subs) and subs != [] -> errors
        nil -> ["events capability requires events.subscribes" | errors]
        _ -> ["events.subscribes must be a non-empty list" | errors]
      end
    else
      errors
    end
  end

  defp maybe_validate_hooks(errors, caps, manifest) do
    if "hooks" in caps, do: validate_hook_points(errors, manifest), else: errors
  end

  defp validate_hook_points(errors, manifest) do
    valid_points = ~w(before_invocation after_invocation on_tool_call on_error)

    case manifest["hooks"] do
      %{"points" => points} when is_list(points) and points != [] ->
        invalid = Enum.reject(points, &(&1 in valid_points))

        if invalid == [],
          do: errors,
          else: ["invalid hook points: #{Enum.join(invalid, ", ")}" | errors]

      nil ->
        ["hooks capability requires hooks.points" | errors]

      _ ->
        ["hooks.points must be a non-empty list" | errors]
    end
  end

  defp maybe_validate_provider(errors, _caps, _manifest), do: errors

  @doc "Returns recognized manifest fields for filtering unknown keys."
  def known_fields, do: @required_fields ++ @optional_fields

  @doc """
  Validate config values against a config_schema (JSON Schema subset).

  Supports: required fields, type checking, numeric bounds (minimum/maximum),
  string bounds (minLength/maxLength), array bounds (minItems/maxItems).

  Returns :ok or {:error, [%{path: String.t(), message: String.t()}]}.
  """
  def validate_config(config, %{"properties" => properties} = schema) do
    errors =
      []
      |> validate_required_config(config, schema)
      |> validate_config_types(config, properties)
      |> validate_config_constraints(config, properties)

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  def validate_config(_config, _schema), do: :ok

  defp validate_required_config(errors, config, %{"required" => required}) do
    Enum.reduce(required, errors, fn key, acc ->
      if Map.has_key?(config, key) do
        acc
      else
        [%{path: key, message: "is required"} | acc]
      end
    end)
  end

  defp validate_required_config(errors, _config, _schema), do: errors

  defp validate_config_types(errors, config, properties) do
    Enum.reduce(config, errors, fn {key, value}, acc ->
      case Map.get(properties, key) do
        nil -> acc
        %{"type" => expected} -> validate_type(acc, key, value, expected)
        _ -> acc
      end
    end)
  end

  defp validate_type(errors, _key, value, "string") when is_binary(value), do: errors

  defp validate_type(errors, key, _value, "string"),
    do: [%{path: key, message: "expected string"} | errors]

  defp validate_type(errors, _key, value, "integer") when is_integer(value), do: errors

  defp validate_type(errors, key, _value, "integer"),
    do: [%{path: key, message: "expected integer"} | errors]

  defp validate_type(errors, _key, value, "number") when is_number(value), do: errors

  defp validate_type(errors, key, _value, "number"),
    do: [%{path: key, message: "expected number"} | errors]

  defp validate_type(errors, _key, value, "boolean") when is_boolean(value), do: errors

  defp validate_type(errors, key, _value, "boolean"),
    do: [%{path: key, message: "expected boolean"} | errors]

  defp validate_type(errors, _key, value, "array") when is_list(value), do: errors

  defp validate_type(errors, key, _value, "array"),
    do: [%{path: key, message: "expected array"} | errors]

  defp validate_type(errors, _key, _value, _type), do: errors

  defp validate_config_constraints(errors, config, properties) do
    Enum.reduce(config, errors, fn {key, value}, acc ->
      case Map.get(properties, key) do
        nil -> acc
        prop_schema -> validate_constraints(acc, key, value, prop_schema)
      end
    end)
  end

  defp validate_constraints(errors, key, value, schema) do
    errors
    |> maybe_validate_minimum(key, value, schema)
    |> maybe_validate_maximum(key, value, schema)
    |> maybe_validate_min_length(key, value, schema)
    |> maybe_validate_max_length(key, value, schema)
    |> maybe_validate_min_items(key, value, schema)
    |> maybe_validate_max_items(key, value, schema)
  end

  defp maybe_validate_minimum(errors, key, value, %{"minimum" => min})
       when is_number(value) and value < min do
    [%{path: key, message: "must be >= #{min}"} | errors]
  end

  defp maybe_validate_minimum(errors, _key, _value, _schema), do: errors

  defp maybe_validate_maximum(errors, key, value, %{"maximum" => max})
       when is_number(value) and value > max do
    [%{path: key, message: "must be <= #{max}"} | errors]
  end

  defp maybe_validate_maximum(errors, _key, _value, _schema), do: errors

  defp maybe_validate_min_length(errors, key, value, %{"minLength" => min})
       when is_binary(value) and byte_size(value) < min do
    [%{path: key, message: "must be at least #{min} characters"} | errors]
  end

  defp maybe_validate_min_length(errors, _key, _value, _schema), do: errors

  defp maybe_validate_max_length(errors, key, value, %{"maxLength" => max})
       when is_binary(value) and byte_size(value) > max do
    [%{path: key, message: "must be at most #{max} characters"} | errors]
  end

  defp maybe_validate_max_length(errors, _key, _value, _schema), do: errors

  defp maybe_validate_min_items(errors, key, value, %{"minItems" => min})
       when is_list(value) and length(value) < min do
    [%{path: key, message: "must have at least #{min} items"} | errors]
  end

  defp maybe_validate_min_items(errors, _key, _value, _schema), do: errors

  defp maybe_validate_max_items(errors, key, value, %{"maxItems" => max})
       when is_list(value) and length(value) > max do
    [%{path: key, message: "must have at most #{max} items"} | errors]
  end

  defp maybe_validate_max_items(errors, _key, _value, _schema), do: errors
end
