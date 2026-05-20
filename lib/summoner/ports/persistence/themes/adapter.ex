defmodule Summoner.Ports.Persistence.Themes.Adapter do
  @moduledoc "Behaviour for themes persistence operations."

  @callback list_themes() :: [struct()]
  @callback get_theme!(String.t()) :: struct()
  @callback get_theme_by_name(String.t()) :: struct() | nil
  @callback create_theme(map()) ::
              {:ok, struct()} | {:error, :theme_limit_reached | Ecto.Changeset.t()}
  @callback delete_theme(struct()) ::
              {:ok, struct()} | {:error, :builtin_theme | Ecto.Changeset.t()}
  @callback import_from_zip(binary()) :: {:ok, struct()} | {:error, term()}
  @callback generate_css() :: String.t()
  @callback write_css_file() :: :ok
  @callback css_file_path() :: String.t()
  @callback seed_builtins() :: :ok
end
