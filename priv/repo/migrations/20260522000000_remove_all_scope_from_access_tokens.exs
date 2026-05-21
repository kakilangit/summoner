defmodule Summoner.Repo.Migrations.RemoveAllScopeFromAccessTokens do
  use Ecto.Migration

  def up do
    # Replace "all" scope with individual non-admin scopes
    execute """
    UPDATE access_tokens
    SET scopes = '{a2a,api,webhook}'
    WHERE 'all' = ANY(scopes)
    """

    # Convert "openai" scope to "api" (openai-compat uses api scope now)
    execute """
    UPDATE access_tokens
    SET scopes = array_replace(scopes, 'openai', 'api')
    WHERE 'openai' = ANY(scopes)
    """

    # Convert "mcp" scope to "api" (MCP server mode uses api scope now)
    execute """
    UPDATE access_tokens
    SET scopes = array_replace(scopes, 'mcp', 'api')
    WHERE 'mcp' = ANY(scopes)
    """

    # Deduplicate: remove duplicate "api" entries after conversion
    execute """
    UPDATE access_tokens
    SET scopes = (SELECT array_agg(DISTINCT s) FROM unnest(scopes) AS s)
    WHERE array_length(scopes, 1) != (SELECT count(DISTINCT s) FROM unnest(scopes) AS s)
    """
  end

  def down do
    # No-op: we can't know which tokens originally had "all", "openai", or "mcp"
    :ok
  end
end
