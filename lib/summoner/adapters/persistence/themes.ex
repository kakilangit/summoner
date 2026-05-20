defmodule Summoner.Adapters.Persistence.Themes do
  @moduledoc """
  Context for theme management.

  Handles CRUD, zip import, CSS generation, and built-in theme seeding.
  """

  import Ecto.Query, warn: false

  alias Summoner.Domain.Schemas.Theme
  alias Summoner.Repo

  @behaviour Summoner.Ports.Persistence.Themes.Adapter

  @max_themes 50
  @max_zip_size 1_048_576

  # -------------------------------------------------------------------
  # Built-in theme definitions
  # -------------------------------------------------------------------

  @elixir_dark %{
    name: "elixir-dark",
    display_name: "Elixir Dark",
    color_scheme: "dark",
    author: "Summoner",
    version: "1.0.0",
    is_builtin: true,
    tokens: %{
      "color-base-100" => "oklch(30.33% 0.016 252.42)",
      "color-base-200" => "oklch(25.26% 0.014 253.1)",
      "color-base-300" => "oklch(20.15% 0.012 254.09)",
      "color-base-content" => "oklch(97.807% 0.029 256.847)",
      "color-primary" => "oklch(58% 0.233 277.117)",
      "color-primary-content" => "oklch(96% 0.018 272.314)",
      "color-secondary" => "oklch(58% 0.233 277.117)",
      "color-secondary-content" => "oklch(96% 0.018 272.314)",
      "color-accent" => "oklch(60% 0.25 292.717)",
      "color-accent-content" => "oklch(96% 0.016 293.756)",
      "color-neutral" => "oklch(37% 0.044 257.287)",
      "color-neutral-content" => "oklch(98% 0.003 247.858)",
      "color-info" => "oklch(58% 0.158 241.966)",
      "color-info-content" => "oklch(97% 0.013 236.62)",
      "color-success" => "oklch(60% 0.118 184.704)",
      "color-success-content" => "oklch(98% 0.014 180.72)",
      "color-warning" => "oklch(66% 0.179 58.318)",
      "color-warning-content" => "oklch(98% 0.022 95.277)",
      "color-error" => "oklch(58% 0.253 17.585)",
      "color-error-content" => "oklch(96% 0.015 12.422)",
      "radius-selector" => "0.25rem",
      "radius-field" => "0.25rem",
      "radius-box" => "0.5rem",
      "size-selector" => "0.21875rem",
      "size-field" => "0.21875rem",
      "border" => "1.5px",
      "depth" => "1",
      "noise" => "0"
    }
  }

  @phoenix_light %{
    name: "phoenix-light",
    display_name: "Phoenix Light",
    color_scheme: "light",
    author: "Summoner",
    version: "1.0.0",
    is_builtin: true,
    tokens: %{
      "color-base-100" => "oklch(98% 0 0)",
      "color-base-200" => "oklch(96% 0.001 286.375)",
      "color-base-300" => "oklch(92% 0.004 286.32)",
      "color-base-content" => "oklch(21% 0.006 285.885)",
      "color-primary" => "oklch(70% 0.213 47.604)",
      "color-primary-content" => "oklch(98% 0.016 73.684)",
      "color-secondary" => "oklch(55% 0.027 264.364)",
      "color-secondary-content" => "oklch(98% 0.002 247.839)",
      "color-accent" => "oklch(0% 0 0)",
      "color-accent-content" => "oklch(100% 0 0)",
      "color-neutral" => "oklch(44% 0.017 285.786)",
      "color-neutral-content" => "oklch(98% 0 0)",
      "color-info" => "oklch(62% 0.214 259.815)",
      "color-info-content" => "oklch(97% 0.014 254.604)",
      "color-success" => "oklch(70% 0.14 182.503)",
      "color-success-content" => "oklch(98% 0.014 180.72)",
      "color-warning" => "oklch(66% 0.179 58.318)",
      "color-warning-content" => "oklch(98% 0.022 95.277)",
      "color-error" => "oklch(58% 0.253 17.585)",
      "color-error-content" => "oklch(96% 0.015 12.422)",
      "radius-selector" => "0.25rem",
      "radius-field" => "0.25rem",
      "radius-box" => "0.5rem",
      "size-selector" => "0.21875rem",
      "size-field" => "0.21875rem",
      "border" => "1.5px",
      "depth" => "1",
      "noise" => "0"
    }
  }

  @builtin_themes [@elixir_dark, @phoenix_light]

  # -------------------------------------------------------------------
  # Queries
  # -------------------------------------------------------------------

  @doc "Lists all installed themes, builtins first."
  def list_themes do
    Theme
    |> order_by([t], desc: t.is_builtin, asc: t.name)
    |> Repo.all()
  end

  @doc "Gets a theme by ID."
  def get_theme!(id), do: Repo.get!(Theme, id)

  @doc "Gets a theme by name."
  def get_theme_by_name(name), do: Repo.get_by(Theme, name: name)

  # -------------------------------------------------------------------
  # Create / Delete
  # -------------------------------------------------------------------

  @doc "Creates a user-installed theme."
  def create_theme(attrs) do
    count = Repo.aggregate(Theme, :count)

    if count >= @max_themes do
      {:error, :theme_limit_reached}
    else
      %Theme{}
      |> Theme.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc "Deletes a theme. Built-in themes cannot be deleted."
  def delete_theme(%Theme{is_builtin: true}), do: {:error, :builtin_theme}

  def delete_theme(%Theme{} = theme) do
    Repo.delete(theme)
  end

  # -------------------------------------------------------------------
  # Zip import
  # -------------------------------------------------------------------

  @doc """
  Imports a theme from a zip file binary.

  The zip must contain a `theme.json` at root level and be under 1 MB.
  Returns `{:ok, theme}` or `{:error, reason}`.
  """
  def import_from_zip(zip_binary) when byte_size(zip_binary) > @max_zip_size do
    {:error, :zip_too_large}
  end

  def import_from_zip(zip_binary) do
    with {:ok, json} <- extract_theme_json(zip_binary),
         {:ok, parsed} <- decode_json(json),
         {:ok, attrs} <- normalize_import(parsed) do
      create_theme(attrs)
    end
  end

  @max_zip_entries 5

  defp extract_theme_json(zip_binary) do
    with {:ok, files} <- unzip_to_memory(zip_binary),
         :ok <- check_zip_entry_count(files) do
      find_theme_json(files)
    end
  end

  defp unzip_to_memory(zip_binary) do
    case :zip.unzip(zip_binary, [:memory]) do
      {:ok, files} -> {:ok, files}
      {:error, _reason} -> {:error, :invalid_zip}
    end
  end

  defp check_zip_entry_count(files) when length(files) <= @max_zip_entries, do: :ok
  defp check_zip_entry_count(_files), do: {:error, :zip_too_many_entries}

  defp find_theme_json(files) do
    case Enum.find(files, fn {name, _data} ->
           Path.basename(to_string(name)) == "theme.json"
         end) do
      {_name, data} -> {:ok, data}
      nil -> {:error, :missing_theme_json}
    end
  end

  defp decode_json(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _other} -> {:error, :invalid_theme_json}
      {:error, _reason} -> {:error, :invalid_json}
    end
  end

  defp normalize_import(parsed) do
    attrs = %{
      name: parsed["name"],
      display_name: parsed["display_name"],
      color_scheme: parsed["color_scheme"],
      author: parsed["author"],
      version: parsed["version"],
      tokens: parsed["tokens"],
      is_builtin: false
    }

    {:ok, attrs}
  end

  # -------------------------------------------------------------------
  # CSS generation
  # -------------------------------------------------------------------

  @doc """
  Generates CSS text for all installed themes.

  Output order matters for the cascade:
  1. `:root` fallback (first light theme defaults)
  2. `@media (prefers-color-scheme: dark)` fallback
  3. All `[data-theme="..."]` selectors (override `:root`)

  This ensures `[data-theme]` always wins over `:root` when both
  have the same specificity (0,1,0) — later source order prevails.
  """
  def generate_css do
    themes = list_themes()

    root_blocks = Enum.flat_map(themes, &root_fallback_css/1)
    theme_blocks = Enum.map(themes, &theme_selector_css/1)

    Enum.join(root_blocks ++ theme_blocks, "\n\n")
  end

  defp root_fallback_css(%Theme{} = theme) do
    {color_scheme, vars} = theme_vars(theme)

    cond do
      theme.name == "phoenix-light" ->
        [":root {\n#{color_scheme}\n#{vars}\n}"]

      theme.color_scheme == "dark" and theme.is_builtin ->
        media =
          "@media (prefers-color-scheme: dark) {\n  :root {\n#{indent(color_scheme, 4)}\n#{indent(vars, 4)}\n  }\n}"

        [media]

      true ->
        []
    end
  end

  defp theme_selector_css(%Theme{} = theme) do
    {color_scheme, vars} = theme_vars(theme)
    "[data-theme=\"#{theme.name}\"] {\n#{color_scheme}\n#{vars}\n}"
  end

  defp theme_vars(%Theme{} = theme) do
    vars =
      theme.tokens
      |> Enum.sort_by(fn {key, _val} -> key end)
      |> Enum.map_join("\n", fn {key, val} -> "  --#{key}: #{val};" end)

    color_scheme = "  color-scheme: #{theme.color_scheme};"

    {color_scheme, vars}
  end

  defp indent(text, spaces) do
    pad = String.duplicate(" ", spaces)

    String.replace(text, "\n", "\n#{pad}")
    |> then(fn s -> "#{pad}#{s}" end)
  end

  @doc """
  Writes the generated CSS to the static assets directory.

  Called on theme install/delete and on application boot.
  """
  def write_css_file do
    css = generate_css()
    path = css_file_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, css)
    :ok
  end

  @doc "Returns the path to the generated themes CSS file."
  def css_file_path do
    Path.join(Application.app_dir(:summoner, "priv/static/assets"), "themes.css")
  end

  # -------------------------------------------------------------------
  # Seeding
  # -------------------------------------------------------------------

  @doc """
  Seeds built-in themes. Idempotent — skips if already present.
  """
  def seed_builtins do
    Enum.each(@builtin_themes, fn attrs ->
      %Theme{}
      |> Theme.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing, conflict_target: :name)
    end)

    write_css_file()
  end
end
