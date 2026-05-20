defmodule Summoner.Domain.Types.EncryptedBinary do
  @moduledoc """
  Encrypted binary field type for Ecto schemas.

  Values are encrypted at rest via Cloak AES-256-GCM using the
  application's configured vault.
  """

  use Cloak.Ecto.Binary, vault: Summoner.Adapters.Crypto.Vault
end
