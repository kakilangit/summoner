defmodule Summoner.Encrypted.Binary do
  @moduledoc """
  Encrypted binary field type for Ecto schemas.
  """

  use Cloak.Ecto.Binary, vault: Summoner.Vault
end
