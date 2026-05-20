#!/bin/sh
# Bundled seed script — creates default workspace, Ollama provider, and General Assistant agent.
# Runs against PostgreSQL directly. All operations are idempotent.
#
# Required env vars:
#   PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE
#   ADMIN_EMAIL — the admin user email (must already exist from app entrypoint)
#   BUNDLED_OLLAMA_URL — Ollama base URL (default: http://ollama:11434)

set -eu

OLLAMA_URL="${BUNDLED_OLLAMA_URL:-http://ollama:11434}"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000000Z")

# Pre-generated NULID UUIDs (timestamp-prefixed, lexicographically sortable)
TENANT_NULID="018afb54-adcf-f896-8330-2a0b7fea8826"
TENANT_MEMBERSHIP_NULID="018afb54-ae9f-a710-1234-5a6b7c8d9e0f"
TENANT_SETTINGS_NULID="018afb54-af6f-b820-2345-6b7c8d9e0f1a"
WORKSPACE_NULID="018af83c-7713-e9e5-811a-de8a077ae07f"
MEMBERSHIP_NULID="018af83c-77de-6846-8bcd-9fe03931a965"
SETTINGS_NULID="018af83c-78a7-9a61-0be1-8516808033e8"
PROVIDER_NULID="018af83c-7970-d92d-804f-4a2e117c1a54"
AGENT_NULID="018af83c-7a39-d12f-9a52-4d6f2580e090"

echo "[Bundled Seed] Waiting for admin user to exist..."
RETRIES=0
MAX_RETRIES=30
while [ $RETRIES -lt $MAX_RETRIES ]; do
  ADMIN_ID=$(psql -tAc "SELECT id FROM users WHERE email = '${ADMIN_EMAIL}'" 2>/dev/null || true)
  if [ -n "$ADMIN_ID" ]; then
    break
  fi
  RETRIES=$((RETRIES + 1))
  echo "[Bundled Seed] Admin user not found yet, retrying ($RETRIES/$MAX_RETRIES)..."
  sleep 2
done

if [ -z "$ADMIN_ID" ]; then
  echo "[Bundled Seed] ERROR: Admin user '${ADMIN_EMAIL}' not found after $MAX_RETRIES attempts."
  exit 1
fi

echo "[Bundled Seed] Admin user found: $ADMIN_ID"

# --- Default Tenant (Realm) ---
TENANT_ID="$TENANT_NULID"
TENANT_NAME="${ADMIN_TENANT:-Default}"

if ! psql -tAc "SELECT 1 FROM tenants WHERE id = '$TENANT_ID' LIMIT 1" | grep -q 1; then
  psql -c "INSERT INTO tenants (id, name, inserted_at, updated_at) VALUES ('$TENANT_ID', '$TENANT_NAME', '$NOW', '$NOW')" > /dev/null
  psql -c "INSERT INTO tenant_memberships (id, tenant_id, user_id, role, inserted_at, updated_at) VALUES ('$TENANT_MEMBERSHIP_NULID', '$TENANT_ID', '$ADMIN_ID', 'admin', '$NOW', '$NOW') ON CONFLICT (tenant_id, user_id) DO NOTHING" > /dev/null
  psql -c "INSERT INTO tenant_settings (id, tenant_id, inserted_at, updated_at) VALUES ('$TENANT_SETTINGS_NULID', '$TENANT_ID', '$NOW', '$NOW') ON CONFLICT (tenant_id) DO NOTHING" > /dev/null
  echo "[Bundled Seed] Default realm created: $TENANT_NAME ($TENANT_ID)"
else
  echo "[Bundled Seed] Default realm already exists: $TENANT_ID"
fi

# --- Workspace ---
WORKSPACE_NAME="Default"
WORKSPACE_ID=$(psql -tAc "SELECT id FROM workspaces WHERE tenant_id = '$TENANT_ID' AND name = '$WORKSPACE_NAME' LIMIT 1")

if [ -z "$WORKSPACE_ID" ]; then
  psql -c "INSERT INTO workspaces (id, tenant_id, name, inserted_at, updated_at) VALUES ('$WORKSPACE_NULID', '$TENANT_ID', '$WORKSPACE_NAME', '$NOW', '$NOW')" > /dev/null
  WORKSPACE_ID="$WORKSPACE_NULID"
  echo "[Bundled Seed] Workspace created: $WORKSPACE_NAME ($WORKSPACE_ID)"

  # Workspace membership for admin
  psql -c "INSERT INTO workspace_memberships (id, workspace_id, user_id, role, inserted_at, updated_at) VALUES ('$MEMBERSHIP_NULID', '$WORKSPACE_ID', '$ADMIN_ID', 'admin', '$NOW', '$NOW') ON CONFLICT (workspace_id, user_id) DO NOTHING" > /dev/null

  # Workspace settings
  psql -c "INSERT INTO workspace_settings (id, workspace_id, inserted_at, updated_at) VALUES ('$SETTINGS_NULID', '$WORKSPACE_ID', '$NOW', '$NOW') ON CONFLICT (workspace_id) DO NOTHING" > /dev/null

  echo "[Bundled Seed] Workspace membership and settings created."
else
  echo "[Bundled Seed] Workspace already exists: $WORKSPACE_NAME ($WORKSPACE_ID)"
fi

# --- Provider ---
PROVIDER_NAME="Ollama"
PROVIDER_ID=$(psql -tAc "SELECT id FROM providers WHERE workspace_id = '$WORKSPACE_ID' AND name = '$PROVIDER_NAME' LIMIT 1")

if [ -z "$PROVIDER_ID" ]; then
  psql -c "INSERT INTO providers (id, workspace_id, name, kind, api_format, type, base_url, status, cached_models, inserted_at, updated_at) VALUES ('$PROVIDER_NULID', '$WORKSPACE_ID', '$PROVIDER_NAME', 'ollama', 'custom', 'local', '$OLLAMA_URL', 'unknown', '{}', '$NOW', '$NOW')" > /dev/null
  PROVIDER_ID="$PROVIDER_NULID"
  echo "[Bundled Seed] Provider created: $PROVIDER_NAME ($PROVIDER_ID)"
else
  echo "[Bundled Seed] Provider already exists: $PROVIDER_NAME ($PROVIDER_ID)"
fi

# --- Agent ---
AGENT_NAME="General Assistant"
AGENT_CALLNAME="general_assistant"
AGENT_ID=$(psql -tAc "SELECT id FROM agents WHERE workspace_id = '$WORKSPACE_ID' AND callname = '$AGENT_CALLNAME' LIMIT 1")

if [ -z "$AGENT_ID" ]; then
  SYSTEM_PROMPT="You are a helpful AI assistant. Answer questions clearly, concisely, and accurately. When uncertain, say so. Break complex topics into understandable parts."
  PERSONALITY="Friendly, patient, and precise. Adapts communication style to the user''s level."
  MODEL="${BUNDLED_MODEL:-qwen3:0.6b}"

  psql -c "INSERT INTO agents (id, workspace_id, name, callname, type, role, inserted_at, updated_at) VALUES ('$AGENT_NULID', '$WORKSPACE_ID', '$AGENT_NAME', '$AGENT_CALLNAME', 'local', 'autonomous', '$NOW', '$NOW')" > /dev/null
  psql -c "INSERT INTO local_agents (agent_id, provider_id, model, system_prompt, personality, max_steps, max_concurrent_invocations, max_delegation_concurrency, max_tokens_per_invocation, step_timeout_s, total_timeout_s, stream_tokens_to_observability) VALUES ('$AGENT_NULID', '$PROVIDER_ID', '$MODEL', '$SYSTEM_PROMPT', '$PERSONALITY', 10, 1, 3, 50000, 60, 300, false)" > /dev/null
  AGENT_ID="$AGENT_NULID"
  echo "[Bundled Seed] Agent created: $AGENT_NAME ($AGENT_ID)"
else
  echo "[Bundled Seed] Agent already exists: $AGENT_NAME ($AGENT_ID)"
fi

echo "[Bundled Seed] Done."
