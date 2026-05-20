defmodule Summoner.Adapters.Persistence.ThemesTest do
  use Summoner.DataCase

  alias Summoner.Adapters.Persistence.Themes
  alias Summoner.Domain.Schemas.Theme

  @valid_tokens %{
    "color-base-100" => "oklch(30% 0.016 252.42)",
    "color-base-200" => "oklch(25% 0.014 253.1)",
    "color-base-300" => "oklch(20% 0.012 254.09)",
    "color-base-content" => "oklch(97% 0.029 256.847)",
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

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "test-theme-#{System.unique_integer([:positive]) |> Integer.to_string()}",
        display_name: "Test Theme",
        color_scheme: "dark",
        author: "Test",
        version: "1.0.0",
        tokens: @valid_tokens
      },
      overrides
    )
  end

  describe "create_theme/1" do
    test "creates a valid theme" do
      attrs = valid_attrs()
      assert {:ok, %Theme{} = theme} = Themes.create_theme(attrs)
      assert theme.name == attrs.name
      assert theme.display_name == "Test Theme"
      assert theme.color_scheme == "dark"
      assert theme.is_builtin == false
      assert map_size(theme.tokens) == 28
    end

    test "rejects duplicate name" do
      attrs = valid_attrs()
      assert {:ok, _theme} = Themes.create_theme(attrs)
      assert {:error, changeset} = Themes.create_theme(attrs)
      assert errors_on(changeset).name == ["has already been taken"]
    end

    test "rejects invalid name format" do
      attrs = valid_attrs(%{name: "Invalid Name!"})
      assert {:error, changeset} = Themes.create_theme(attrs)
      assert errors_on(changeset).name != []
    end

    test "rejects missing tokens" do
      attrs = valid_attrs(%{tokens: Map.delete(@valid_tokens, "color-primary")})
      assert {:error, changeset} = Themes.create_theme(attrs)
      assert errors_on(changeset).tokens != []
    end

    test "rejects extra tokens" do
      attrs = valid_attrs(%{tokens: Map.put(@valid_tokens, "custom-thing", "value")})
      assert {:error, changeset} = Themes.create_theme(attrs)
      assert errors_on(changeset).tokens != []
    end

    test "rejects invalid oklch values" do
      attrs = valid_attrs(%{tokens: Map.put(@valid_tokens, "color-primary", "rgb(255,0,0)")})
      assert {:error, changeset} = Themes.create_theme(attrs)
      assert errors_on(changeset).tokens != []
    end

    test "rejects invalid color_scheme" do
      attrs = valid_attrs(%{color_scheme: "neon"})
      assert {:error, changeset} = Themes.create_theme(attrs)
      assert errors_on(changeset).color_scheme != []
    end
  end

  describe "delete_theme/1" do
    test "deletes a user-installed theme" do
      {:ok, theme} = Themes.create_theme(valid_attrs())
      assert {:ok, _} = Themes.delete_theme(theme)
      assert Themes.get_theme_by_name(theme.name) == nil
    end

    test "refuses to delete a builtin theme" do
      {:ok, theme} = Themes.create_theme(valid_attrs(%{is_builtin: true}))
      assert {:error, :builtin_theme} = Themes.delete_theme(theme)
    end
  end

  describe "list_themes/0" do
    test "lists all themes" do
      {:ok, _} = Themes.create_theme(valid_attrs())
      assert Themes.list_themes() != []
    end
  end

  describe "import_from_zip/1" do
    test "imports a valid theme zip" do
      attrs = valid_attrs()

      json =
        Jason.encode!(%{
          name: attrs.name,
          display_name: attrs.display_name,
          color_scheme: attrs.color_scheme,
          author: attrs.author,
          version: attrs.version,
          tokens: attrs.tokens
        })

      {:ok, {_zip_path, zip_binary}} =
        :zip.create(~c"theme.zip", [{~c"theme.json", json}], [:memory])

      assert {:ok, %Theme{} = theme} = Themes.import_from_zip(zip_binary)
      assert theme.name == attrs.name
    end

    test "rejects zip without theme.json" do
      {:ok, {_path, zip_binary}} =
        :zip.create(~c"test.zip", [{~c"readme.txt", "hello"}], [:memory])

      assert {:error, :missing_theme_json} = Themes.import_from_zip(zip_binary)
    end

    test "rejects oversized zip" do
      big = :binary.copy(<<0>>, 1_048_577)
      assert {:error, :zip_too_large} = Themes.import_from_zip(big)
    end

    test "rejects invalid zip" do
      assert {:error, :invalid_zip} = Themes.import_from_zip("not a zip")
    end
  end

  describe "generate_css/0" do
    test "generates CSS blocks for themes" do
      {:ok, _} = Themes.create_theme(valid_attrs(%{name: "css-test-theme"}))
      css = Themes.generate_css()
      assert css =~ "[data-theme=\"css-test-theme\"]"
      assert css =~ "color-scheme: dark"
    end
  end

  describe "seed_builtins/0" do
    test "seeds elixir-dark and phoenix-light" do
      Themes.seed_builtins()
      assert %Theme{is_builtin: true} = Themes.get_theme_by_name("elixir-dark")
      assert %Theme{is_builtin: true} = Themes.get_theme_by_name("phoenix-light")
    end

    test "is idempotent" do
      Themes.seed_builtins()
      Themes.seed_builtins()
      assert %Theme{} = Themes.get_theme_by_name("elixir-dark")
    end
  end
end
