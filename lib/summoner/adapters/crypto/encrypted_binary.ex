defmodule Summoner.Adapters.Crypto.EncryptedBinary do
  @moduledoc """
  Deprecated — use `Summoner.Domain.Types.EncryptedBinary` instead.

  Kept for backward compatibility with existing migration references.
  """

  use Cloak.Ecto.Binary, vault: Summoner.Adapters.Crypto.Vault
end
