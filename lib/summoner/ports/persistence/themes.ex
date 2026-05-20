defmodule Summoner.Ports.Persistence.Themes do
  @moduledoc "Port for themes persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :themes],
             Summoner.Adapters.Persistence.Themes
           )

  defdelegate list_themes(), to: @adapter
  defdelegate get_theme!(id), to: @adapter
  defdelegate get_theme_by_name(name), to: @adapter
  defdelegate create_theme(attrs), to: @adapter
  defdelegate delete_theme(theme), to: @adapter
  defdelegate import_from_zip(zip_binary), to: @adapter
  defdelegate generate_css(), to: @adapter
  defdelegate write_css_file(), to: @adapter
  defdelegate css_file_path(), to: @adapter
  defdelegate seed_builtins(), to: @adapter
end
