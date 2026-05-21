defmodule Summoner.Domain.Policies.WebhookAuthTest do
  use ExUnit.Case, async: true

  alias Summoner.Domain.Policies.WebhookAuth

  describe "verify/2" do
    test "public mode always succeeds" do
      assert :ok == WebhookAuth.verify(%{auth_mode: :public}, [])
    end

    test "token mode succeeds when token is valid" do
      assert :ok == WebhookAuth.verify(%{auth_mode: :token}, token_valid: true)
    end

    test "token mode fails when token is invalid" do
      assert {:error, :unauthorized} ==
               WebhookAuth.verify(%{auth_mode: :token}, token_valid: false)
    end

    test "token mode fails when no token provided" do
      assert {:error, :unauthorized} == WebhookAuth.verify(%{auth_mode: :token}, [])
    end

    test "hmac mode succeeds with valid signature" do
      secret = "my-secret"
      body = ~s({"hello":"world"})
      digest = :crypto.mac(:hmac, :sha256, secret, body)
      hex = Base.encode16(digest, case: :lower)
      signature = "sha256=#{hex}"

      assert :ok ==
               WebhookAuth.verify(%{auth_mode: :hmac},
                 signature: signature,
                 raw_body: body,
                 secret_value: secret
               )
    end

    test "hmac mode fails with wrong signature" do
      assert {:error, :unauthorized} ==
               WebhookAuth.verify(%{auth_mode: :hmac},
                 signature: "sha256=deadbeef",
                 raw_body: "body",
                 secret_value: "secret"
               )
    end

    test "hmac mode fails with nil signature" do
      assert {:error, :unauthorized} ==
               WebhookAuth.verify(%{auth_mode: :hmac},
                 signature: nil,
                 raw_body: "body",
                 secret_value: "secret"
               )
    end
  end

  describe "verify_hmac/3" do
    test "returns false for nil inputs" do
      refute WebhookAuth.verify_hmac(nil, "body", "secret")
      refute WebhookAuth.verify_hmac("sha256=abc", nil, "secret")
      refute WebhookAuth.verify_hmac("sha256=abc", "body", nil)
    end

    test "returns false for non-sha256 prefix" do
      refute WebhookAuth.verify_hmac("md5=abc", "body", "secret")
    end
  end
end
