defmodule Summoner.Adapters.Crypto.EncryptedBinary do
  @moduledoc """
  Encrypted binary field type for Ecto schemas.
  """

  use Cloak.Ecto.Binary, vault: Summoner.Adapters.Crypto.Vault
end
