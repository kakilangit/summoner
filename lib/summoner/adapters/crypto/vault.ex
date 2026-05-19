defmodule Summoner.Adapters.Crypto.Vault do
  @moduledoc """
  Cloak vault for encrypting sensitive data at rest (e.g., API keys).

  Configured via `CLOAK_KEY` environment variable (Base64-encoded 32-byte key).

  Generate a key:

      32 |> :crypto.strong_rand_bytes() |> Base.encode64()
  """

  use Cloak.Vault, otp_app: :summoner
end
