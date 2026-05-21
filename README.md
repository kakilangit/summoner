# Summoner

Local-first, multi-user, multi-workspace AI agent platform.

Built with Elixir 1.19 / Phoenix 1.8 (LiveView) / PostgreSQL 18 (pgvector) / Oban.

## Features

- Multi-workspace with role-based access (owner, admin, editor, operator, viewer)
- AI agent orchestration with ReAct loop, delegation, and tool use
- Provider support: Ollama, OpenAI, Anthropic, DeepSeek, xAI, OpenRouter, GitHub Copilot
- MCP server integration (stdio and SSE transports)
- Pipelines (sequential/orchestrated multi-agent workflows)
- Swarms (Circle, Chain, Command multi-agent collaboration)
- A2A protocol support (Herald server, Envoy remote agents, skill-aware invocation)
- REST API with OpenAPI 3.1 spec and Swagger UI
- Webhooks (Beacons) — trigger agents from external systems (GitHub, CI/CD, etc.)
- Backup agents with ordered failover chains (automatic retry on failure)
- OpenAI-compatible API (`/v1/chat/completions`, `/v1/models`) with streaming support
- Hexagonal architecture with persistence ports, worker ports, and domain event system
- Media generation (images, video) via configurable media providers
- Skill system with vector embeddings (pgvector)
- Token usage tracking and cost budgeting
- Custom themes

## Documentation

See the [`docs/`](docs/) directory for full documentation, or generate a standalone HTML site:

```sh
make docs
# Output: docs/_site/index.html
```

## Requirements

- Elixir 1.19+ / OTP 28+
- PostgreSQL 18+ with pgvector extension
- Rust (for NULID NIF compilation)
- Node.js (for asset compilation)

## Development Setup

```sh
# Start PostgreSQL (pgvector on port 25432)
make infra

# Install deps, create DB, compile assets
make setup

# Start the dev server
make server

# Or with IEx shell
make iex
```

## Commands

```sh
make infra          # docker compose up (PostgreSQL)
make infra.down     # docker compose down
make infra.logs     # docker compose logs

make setup          # full dev setup
make server         # start Phoenix server
make iex            # start with IEx shell

make fmt            # format code
make lint           # format check + credo strict + compile warnings
make test           # run tests
make ci             # lint + test

make db.setup       # create + migrate + seed
make db.migrate     # run pending migrations

make docs           # generate HTML docs from docs/*.md

make release        # build production release
```

## Production Deployment

### Docker

Pre-built multi-arch images (amd64 + arm64) are available on GitHub Container Registry:

```sh
docker pull ghcr.io/kakilangit/summoner:latest
```

### Docker Compose

```sh
cp .env.example .env
# Edit .env with your values
make docker.up
# Or: docker compose -f docker-compose.bundled.yml up -d
```

### Environment Variables

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | `ecto://USER:PASS@HOST/DATABASE` |
| `SECRET_KEY_BASE` | Yes | Generate with `mix phx.gen.secret` |
| `CLOAK_KEY` | Yes | Generate with `32 \|> :crypto.strong_rand_bytes() \|> Base.encode64()` |
| `ADMIN_EMAIL` | Yes | Initial admin user email |
| `ADMIN_PASSWORD` | Yes | Initial admin user password |
| `PHX_HOST` | No | Hostname (default: `localhost`) |
| `PHX_SCHEME` | No | URL scheme: `http` or `https` (default: `https`) |
| `PORT` | No | Host HTTP port (default: `4000`) |
| `POOL_SIZE` | No | DB connection pool size (default: `10`) |
| `SMTP_HOST` | No | SMTP server for email delivery |
| `SMTP_PORT` | No | SMTP port (default: `587`) |
| `SMTP_USER` | No | SMTP username |
| `SMTP_PASSWORD` | No | SMTP password |
| `SMTP_FROM` | No | Sender email address |
| `SMTP_SSL` | No | Enable SMTP SSL (default: `false`) |
| `COPILOT_CLIENT_ID` | No | GitHub Copilot OAuth client ID |

### Docker Build (Local)

Multi-arch images (amd64 + arm64) are published to `ghcr.io/kakilangit/summoner`:

```sh
make build                            # build all images locally
make build DOCKER_TAG=v0.1.4          # build with specific tag
```
