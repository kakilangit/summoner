defmodule Summoner.Ports.Persistence.AccessTokens do
  @moduledoc "Port for access token persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :access_tokens],
             Summoner.Adapters.Persistence.AccessTokens
           )

  defdelegate list_tokens(workspace_id), to: @adapter
  defdelegate list_tokens(workspace_id, opts), to: @adapter
  defdelegate get_token!(workspace_id, id), to: @adapter
  defdelegate create_token(attrs), to: @adapter
  defdelegate update_token(token, attrs), to: @adapter
  defdelegate revoke_token(token), to: @adapter
  defdelegate verify_token(workspace_id, plaintext), to: @adapter
  defdelegate verify_token(workspace_id, plaintext, required_scope), to: @adapter
end
