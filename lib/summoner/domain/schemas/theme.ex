defmodule Summoner.Domain.Schemas.Theme do
  @moduledoc """
  Schema for installable UI themes.

  Each theme maps to a DaisyUI `[data-theme]` block generated from
  its `tokens` map. Names are globally unique per installation.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  @name_format ~r/^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$/
  @max_display_name 100
  @max_author 100
  @max_version 20

  @required_tokens ~w(
    color-base-100 color-base-200 color-base-300 color-base-content
    color-primary color-primary-content
    color-secondary color-secondary-content
    color-accent color-accent-content
    color-neutral color-neutral-content
    color-info color-info-content
    color-success color-success-content
    color-warning color-warning-content
    color-error color-error-content
    radius-selector radius-field radius-box
    size-selector size-field
    border depth noise
  )

  @color_schemes ~w(dark light)

  schema "themes" do
    field :name, :string
    field :display_name, :string
    field :color_scheme, :string
    field :author, :string
    field :version, :string
    field :tokens, :map
    field :is_builtin, :boolean, default: false

    timestamps()
  end

  def required_tokens, do: @required_tokens

  @doc """
  Changeset for creating or updating a theme.
  """
  def changeset(theme, attrs) do
    theme
    |> cast(attrs, [:name, :display_name, :color_scheme, :author, :version, :tokens, :is_builtin])
    |> validate_required([:name, :display_name, :color_scheme, :tokens])
    |> validate_format(:name, @name_format, message: "must be lowercase kebab-case, 2-64 chars")
    |> validate_length(:display_name, max: @max_display_name)
    |> validate_length(:author, max: @max_author)
    |> validate_length(:version, max: @max_version)
    |> validate_inclusion(:color_scheme, @color_schemes)
    |> reject_html(:display_name)
    |> reject_html(:author)
    |> reject_html(:version)
    |> validate_tokens()
    |> unique_constraint(:name)
  end

  @html_tag_regex ~r/[<>&"']/

  defp reject_html(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      val when is_binary(val) ->
        if Regex.match?(@html_tag_regex, val) do
          add_error(changeset, field, "must not contain HTML characters (<, >, &, \", ')")
        else
          changeset
        end

      _other ->
        changeset
    end
  end

  defp validate_tokens(changeset) do
    case get_change(changeset, :tokens) do
      nil ->
        changeset

      tokens when is_map(tokens) ->
        provided = MapSet.new(Map.keys(tokens))
        required = MapSet.new(@required_tokens)
        missing = MapSet.difference(required, provided)
        extra = MapSet.difference(provided, required)

        changeset
        |> maybe_add_missing_error(missing)
        |> maybe_add_extra_error(extra)
        |> validate_oklch_values(tokens)
        |> validate_layout_values(tokens)

      _other ->
        add_error(changeset, :tokens, "must be a map")
    end
  end

  defp maybe_add_missing_error(changeset, missing) do
    if MapSet.size(missing) > 0 do
      add_error(changeset, :tokens, "missing required tokens: #{Enum.join(missing, ", ")}")
    else
      changeset
    end
  end

  defp maybe_add_extra_error(changeset, extra) do
    if MapSet.size(extra) > 0 do
      add_error(changeset, :tokens, "unknown tokens: #{Enum.join(extra, ", ")}")
    else
      changeset
    end
  end

  @oklch_regex ~r/^oklch\(\s*[\d.]+%?\s+[\d.]+\s+[\d.]+\s*\)$/
  @color_token_prefix "color-"

  # Strict allowlists for non-color token values to prevent CSS injection.
  # radius-*: CSS length (e.g. "0.25rem", "4px", "0")
  # size-*:   CSS length
  # border:   CSS length (e.g. "1.5px", "0")
  # depth:    integer 0-5
  # noise:    integer 0-1
  @css_length_regex ~r/^[\d.]+(rem|em|px|%)?$/
  @depth_regex ~r/^[0-5]$/
  @noise_regex ~r/^[01]$/

  @layout_validators %{
    "radius-selector" => @css_length_regex,
    "radius-field" => @css_length_regex,
    "radius-box" => @css_length_regex,
    "size-selector" => @css_length_regex,
    "size-field" => @css_length_regex,
    "border" => @css_length_regex,
    "depth" => @depth_regex,
    "noise" => @noise_regex
  }

  defp validate_oklch_values(changeset, tokens) do
    invalid =
      tokens
      |> Enum.filter(fn {key, _val} -> String.starts_with?(key, @color_token_prefix) end)
      |> Enum.reject(fn {_key, val} -> Regex.match?(@oklch_regex, to_string(val)) end)
      |> Enum.map(fn {key, _val} -> key end)

    if invalid == [] do
      changeset
    else
      add_error(changeset, :tokens, "invalid oklch() values for: #{Enum.join(invalid, ", ")}")
    end
  end

  defp validate_layout_values(changeset, tokens) do
    invalid =
      @layout_validators
      |> Enum.reject(fn {key, regex} ->
        case Map.get(tokens, key) do
          nil -> true
          val -> Regex.match?(regex, to_string(val))
        end
      end)
      |> Enum.map(fn {key, _regex} -> key end)

    if invalid == [] do
      changeset
    else
      add_error(changeset, :tokens, "invalid layout values for: #{Enum.join(invalid, ", ")}")
    end
  end
end
