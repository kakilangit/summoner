defmodule Summoner.Adapters.Persistence.AccessTokensFixtures do
  @moduledoc """
  Test helpers for creating access token entities.
  """

  alias Summoner.Adapters.Persistence.AccessTokens

  def access_token_fixture(workspace_id, tenant_id, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          label: "test-token-#{System.unique_integer([:positive])}",
          workspace_id: workspace_id,
          tenant_id: tenant_id,
          scopes: ["api"],
          rate_limit_rpm: 100
        },
        attrs
      )

    {:ok, token} = AccessTokens.create_token(attrs)
    token
  end
end
