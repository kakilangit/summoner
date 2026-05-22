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

  defp maybe_validate_provider(errors, caps, manifest) do
    if "provider" in caps do
      case manifest["provider"] do
        %{"name" => name} when is_binary(name) and name != "" -> errors
        nil -> ["provider capability requires provider.name" | errors]
        _ -> ["provider.name must be a non-empty string" | errors]
      end
    else
      errors
    end
  end

  @doc "Returns recognized manifest fields for filtering unknown keys."
  def known_fields, do: @required_fields ++ @optional_fields
end
