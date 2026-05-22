# Grimoires (Plugins)

Grimoires extend Summoner with external capabilities packaged as OCI container images. Each grimoire runs as an isolated container and communicates with Summoner over bidirectional HTTP.

## Concepts

| Term | Description |
|------|-------------|
| **Grimoire** | A plugin — an OCI container image with a `grimoire.json` manifest |
| **Manifest** | `grimoire.json` inside the container, declaring capabilities, config, and resource requirements |
| **Ref** | First 12 characters of the SHA-256 hash of the image path (without tag) |
| **Capability** | What the plugin can do: `tools`, `webhooks`, `hooks`, `events`, `provider`, `theme` |

## Architecture

Summoner uses a shared-container model: one container per unique image digest, shared across all installations of that image. Configuration is sent per-request, not baked into the container.

```
Summoner ──HTTP──▶ Plugin Container
   ▲                    │
   └────callback API────┘
```

**Summoner to Plugin**: webhook forwarding, hook execution, event delivery, model listing, chat completion.

**Plugin to Summoner**: invoke agent (sync/async), emit events, log messages.

## Capabilities

### `webhooks` (tested with grimoire-slack)

External HTTP requests are forwarded to the plugin. Routes are declared in `grimoire.json`:

```json
{
  "webhooks": {
    "routes": ["events", "commands", "interactions"]
  }
}
```

Inbound URL pattern: `POST /api/v1/plugins/:plugin_id/hook/:route`

### `events` (tested with grimoire-slack)

The plugin subscribes to Summoner domain events (invocation lifecycle, approvals, etc.):

```json
{
  "events": {
    "subscribes": [
      "invocation.completed",
      "invocation.failed",
      "approval.pending",
      "approval.resolved"
    ]
  }
}
```

Events are delivered as HTTP POST requests to the plugin's `/event` endpoint.

### `tools` (tested with grimoire-slack)

The plugin provides MCP tools to agents. Expected tools are declared in the manifest:

```json
{
  "tools": {
    "expected": ["slack_send_message", "slack_send_reply"]
  }
}
```

### `hooks` (not yet tested)

Lifecycle hooks execute at specific points in the invocation pipeline: `before_invocation`, `after_invocation`, `on_tool_call`, `on_error`. A circuit breaker protects against failing hooks.

### `provider` (not yet tested)

The plugin acts as an LLM provider, exposing `/models` and `/chat` endpoints.

### `theme` (not yet tested)

The plugin provides a custom UI theme.

## Manifest (`grimoire.json`)

Full example from `grimoire-slack`:

```json
{
  "name": "grimoire-slack",
  "ref": "f73c29c6048f",
  "version": "0.1.0",
  "summoner": ">= 0.1.13",
  "description": "Bidirectional Slack integration for Summoner",
  "image": "ghcr.io/kakilangit/grimoire-slack:0.1.0",
  "capabilities": ["webhooks", "events", "tools"],
  "webhooks": {
    "routes": ["events", "commands", "interactions"]
  },
  "events": {
    "subscribes": [
      "invocation.completed",
      "invocation.failed",
      "approval.pending",
      "approval.resolved"
    ]
  },
  "tools": {
    "expected": [
      "slack_send_message",
      "slack_send_reply",
      "slack_add_reaction",
      "slack_list_channels"
    ]
  },
  "config_schema": {
    "type": "object",
    "properties": {
      "bot_token": {
        "type": "string",
        "src": "secret",
        "description": "Slack Bot User OAuth Token (xoxb-...)"
      },
      "signing_secret": {
        "type": "string",
        "src": "secret",
        "description": "Slack app signing secret for webhook verification"
      },
      "default_agent": {
        "type": "string",
        "src": "agent",
        "description": "Default agent for DMs and unrouted messages"
      }
    },
    "required": ["bot_token", "signing_secret", "default_agent"]
  },
  "network": true,
  "resources": {
    "cpu": "0.25",
    "memory": "128Mi"
  }
}
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Plugin identifier |
| `ref` | Yes | 12-char SHA-256 prefix of image path (without tag) |
| `version` | Yes | SemVer version |
| `summoner` | Yes | Minimum Summoner version required |
| `description` | Yes | Human-readable description |
| `image` | Yes | Full OCI image reference with tag |
| `capabilities` | Yes | Array of capability strings |
| `config_schema` | No | JSON Schema for plugin configuration |
| `network` | No | Whether the container needs network access (default: `false`) |
| `resources` | No | CPU and memory limits |

### Config Schema `src` Types

Config properties with a `src` field are resolved from Summoner resources:

- `"src": "secret"` — value comes from an encrypted Seal (secret) in the workspace
- `"src": "agent"` — value is an agent callname from the workspace

## Computing the Ref

The ref is the first 12 characters of the SHA-256 hash of the image path (without tag):

```sh
printf '%s' "ghcr.io/kakilangit/grimoire-slack" | shasum -a 256 | cut -c1-12
# f73c29c6048f
```

## Installation

1. Navigate to **Grimoires** in the workspace sidebar
2. Click **Install** and enter the OCI image reference (e.g. `ghcr.io/kakilangit/grimoire-slack:0.1.0`)
3. Summoner pulls the image, extracts `grimoire.json`, validates the manifest, and creates the installation
4. Configure the plugin (secrets, agent mappings) on the plugin detail page
5. Enable the plugin — Summoner starts (or reuses) the container

## Container Lifecycle

- **Shared containers**: Multiple installations of the same image share one container. Config is sent per-request.
- **Health checks**: Every 30 seconds. Auto-restart on failure (max 3 retries).
- **Orphan sweep**: Containers whose image digest has no enabled installations are automatically removed.
- **Version-less naming**: Container names strip the tag, so image upgrades naturally replace existing containers.
- **Host mode (dev)**: `plugin_host_mode: :host` publishes a random port and uses `localhost`.
- **Docker mode (prod)**: Containers communicate via Docker DNS.

## Developing a Plugin

Plugins are Rust binaries using the `grimoire-sdk` crate. See [grimoire](https://github.com/kakilangit/grimoire) for the SDK and example plugins.

The plugin contract is defined in `priv/openapi/plugin_contract.yaml` (OpenAPI 3.1). Both the Elixir serializer and the Rust SDK types must match these schemas.
