defmodule Summoner.Domain.Schema do
  @moduledoc """
  Base schema module for all Summoner Ecto schemas.

  Sets NULID as the default primary key and foreign key type.

  ## Usage

      defmodule Summoner.Domain.Schemas.Workspace do
        use Summoner.Domain.Schema

        schema "workspaces" do
          field :name, :string
          timestamps()
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, Nulid.Ecto, autogenerate: true}
      @foreign_key_type Nulid.Ecto
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
