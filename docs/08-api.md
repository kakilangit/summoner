# REST API & Webhooks

Summoner exposes a REST API for programmatic access and webhooks (Beacons) for event-driven agent invocation from external systems.

## Authentication

All API endpoints (except webhook triggers) require a Bearer token:

```
Authorization: Bearer shk_<token>
```

Create tokens (Wards) in the UI at **Realm → Wards → New Ward**, or via the API itself.

### Token Scopes

| Scope | Access |
|-------|--------|
| `api` | REST API, OpenAI-compat (future), MCP (future) |
| `a2a` | Agent-to-Agent protocol (Herald) |
| `admin` | Elevated operations (tenant/user management) |
| `webhook` | Webhook trigger authentication (token mode) |

## API Format

- **Base URL**: `/api/v1`
- **Single resources**: returned as flat JSON objects (no `data` wrapper)
- **Lists**: `{ "items": [...], "meta": { "page": 1, "per_page": 20, "total_entries": 42, "total_pages": 3 } }`
- **Request bodies**: flat attributes (no resource key wrapper)
- **Pagination**: `?page=1&per_page=20` (default 20, max 100)

## OpenAPI Spec

- **Spec**: `GET /api/v1/openapi` (JSON)
- **Swagger UI**: `/dev/swaggerui` (dev only)

The spec is auto-generated from controller annotations via `open_api_spex`.

## Endpoints

### Agents

```
GET    /api/v1/agents          List agents
POST   /api/v1/agents          Create agent
GET    /api/v1/agents/:id      Get agent
PUT    /api/v1/agents/:id      Update agent
DELETE /api/v1/agents/:id      Delete agent
POST   /api/v1/agents/:id/invoke   Invoke agent (sync)
POST   /api/v1/agents/:id/stream   Invoke agent (SSE stream)
```

### Conversations

```
GET    /api/v1/conversations              List conversations
POST   /api/v1/conversations              Create conversation
GET    /api/v1/conversations/:id          Get conversation
DELETE /api/v1/conversations/:id          Delete conversation
GET    /api/v1/conversations/:id/messages List messages
GET    /api/v1/conversations/:id/export   Export conversation
```

### Pipelines

```
GET    /api/v1/pipelines              List pipelines
POST   /api/v1/pipelines              Create pipeline
GET    /api/v1/pipelines/:id          Get pipeline
PUT    /api/v1/pipelines/:id          Update pipeline
DELETE /api/v1/pipelines/:id          Delete pipeline
GET    /api/v1/pipelines/:id/runs     List pipeline runs
```

### Swarms

```
GET    /api/v1/swarms          List swarms
POST   /api/v1/swarms          Create swarm
GET    /api/v1/swarms/:id      Get swarm
PUT    /api/v1/swarms/:id      Update swarm
DELETE /api/v1/swarms/:id      Delete swarm
```

### Providers, Secrets, MCP Servers, Skills, Media Providers

All follow the same CRUD pattern:

```
GET    /api/v1/{resource}          List
POST   /api/v1/{resource}          Create
GET    /api/v1/{resource}/:id      Get
PUT    /api/v1/{resource}/:id      Update
DELETE /api/v1/{resource}/:id      Delete
```

Resources: `providers`, `secrets`, `mcp-servers`, `skills`, `media-providers`

### Invocations

```
GET    /api/v1/invocations/:id          Get invocation
GET    /api/v1/invocations/:id/steps    Get invocation steps
GET    /api/v1/invocations/:id/events   Get invocation events
POST   /api/v1/invocations/:id/cancel   Cancel invocation
```

### Usage & Admin

```
GET    /api/v1/usages                  Rolling 30-day usage stats
GET    /api/v1/usages/breakdowns       Usage breakdowns by agent/provider

GET    /api/v1/admin/tenants           List tenants (admin scope)
GET    /api/v1/admin/users             List users (admin scope)
PATCH  /api/v1/admin/users/:id         Update user (admin scope)
GET    /api/v1/admin/invitations       List invitations (admin scope)
GET    /api/v1/admin/stats             System stats (admin scope)
```

## Webhooks (Beacons)

Webhooks allow external systems to trigger agent invocations via HTTP POST.

### CRUD (requires `api` scope)

```
GET    /api/v1/webhooks          List webhooks
POST   /api/v1/webhooks          Create webhook
GET    /api/v1/webhooks/:id      Get webhook
PUT    /api/v1/webhooks/:id      Update webhook
DELETE /api/v1/webhooks/:id      Delete webhook
```

### Trigger (self-authenticated)

```
POST   /api/v1/webhooks/:id/trigger
```

The trigger endpoint does **not** use the standard `api` scope token. Instead, each webhook defines its own authentication:

| Auth Mode | How |
|-----------|-----|
| `public` | No authentication required |
| `token` | `Authorization: Bearer shk_...` with `webhook` scope |
| `hmac` | `X-Signature-256: sha256=<hex>` (GitHub-compatible HMAC-SHA256) |

### Response Modes

| Mode | Behavior |
|------|----------|
| `async` | Returns `202 Accepted` with `conversation_id` immediately |
| `sync` | Holds connection until invocation completes, returns result |
| `stream` | SSE stream with `event: token` and `event: done` events |

### Input Transformation

Webhooks can transform incoming payloads using template interpolation:

```
#{$.pull_request.title}  →  extracts body.pull_request.title
#{$.sender.login}        →  extracts body.sender.login
```

Set the `transform` field to a template string. The interpolated result becomes the `message` sent to the target agent.

### Example: GitHub Webhook

1. Create a webhook targeting your code review agent:

```sh
curl -X POST /api/v1/webhooks \
  -H "Authorization: Bearer shk_..." \
  -d '{
    "name": "github-pr",
    "target_type": "agent",
    "target_id": "01HC...",
    "auth_mode": "hmac",
    "hmac_secret_id": "01HC...",
    "response_mode": "async",
    "transform": "Review PR #{$.pull_request.title} by #{$.sender.login}"
  }'
```

2. Configure GitHub to send webhooks to:
   ```
   POST https://your-summoner.com/api/v1/webhooks/<id>/trigger
   ```

3. Set the webhook secret in GitHub to match the Seal (secret) referenced by `hmac_secret_id`.

### Rate Limiting

Each webhook has a configurable `rate_limit_rpm` (default: 30 requests per minute). Exceeding the limit returns `429 Too Many Requests`.
