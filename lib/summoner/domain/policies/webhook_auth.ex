defmodule Summoner.Domain.Policies.WebhookAuth do
  @moduledoc """
  Pure auth verification for webhook triggers.

  Supports three auth modes:
  - `:public` — no authentication required
  - `:token` — Bearer token validated against unified access token system
  - `:hmac` — GitHub-style HMAC-SHA256 signature verification
  """

  @doc """
  Verifies that a webhook trigger request is authorized.

  For `:hmac` mode, `secret_value` must be the decrypted HMAC secret value.
  For `:token` mode, the caller must verify the token externally and pass `:ok`.
  """
  @spec verify(struct(), keyword()) :: :ok | {:error, :unauthorized}
  def verify(%{auth_mode: :public}, _opts), do: :ok

  def verify(%{auth_mode: :token}, opts) do
    case Keyword.get(opts, :token_valid) do
      true -> :ok
      _ -> {:error, :unauthorized}
    end
  end

  def verify(%{auth_mode: :hmac}, opts) do
    signature = Keyword.get(opts, :signature)
    body = Keyword.get(opts, :raw_body)
    secret_value = Keyword.get(opts, :secret_value)

    case verify_hmac(signature, body, secret_value) do
      true -> :ok
      false -> {:error, :unauthorized}
    end
  end

  @doc "Verify HMAC-SHA256 signature in GitHub format (sha256=hex)."
  @spec verify_hmac(String.t() | nil, binary() | nil, String.t() | nil) :: boolean()
  def verify_hmac(nil, _body, _secret), do: false
  def verify_hmac(_sig, nil, _secret), do: false
  def verify_hmac(_sig, _body, nil), do: false

  def verify_hmac("sha256=" <> hex_digest, body, secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, body)
    expected_hex = Base.encode16(expected, case: :lower)
    Plug.Crypto.secure_compare(hex_digest, expected_hex)
  end

  def verify_hmac(_sig, _body, _secret), do: false
end
