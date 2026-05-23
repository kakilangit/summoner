# Installation

## Requirements

- Elixir 1.19+ / OTP 28+
- PostgreSQL 18 with [pgvector](https://github.com/pgvector/pgvector) extension
- Rust toolchain (for the NULID NIF dependency)
- Docker (optional, for the bundled PostgreSQL)

## Clone

```sh
git clone --recurse-submodules https://github.com/kakilangit/summoner.git
cd summoner
```

## Environment

Copy the example environment file and fill in the required values:

```sh
cp .env.example .env
```

Required variables:

| Variable | Description |
|----------|-------------|
| `SECRET_KEY_BASE` | Phoenix secret key (`mix phx.gen.secret`) |
| `CLOAK_KEY` | Encryption key for secrets at rest (see below) |
| `DATABASE_URL` | PostgreSQL connection string |
| `ADMIN_EMAIL` | Root admin email (created on seed) |
| `ADMIN_PASSWORD` | Root admin password (min 12 chars) |

Generate `CLOAK_KEY`:

```elixir
32 |> :crypto.strong_rand_bytes() |> Base.encode64()
```

Optional variables:

| Variable | Description |
|----------|-------------|
| `PHX_HOST` | Hostname for the application (default: `localhost`) |
| `PORT` | HTTP port (default: `4200`) |
| `COPILOT_CLIENT_ID` | GitHub Copilot OAuth client ID |

## Infrastructure

Start PostgreSQL with pgvector via Docker:

```sh
make infra
```

This runs `docker compose up -d` which starts PostgreSQL on port 25432.

## Setup

Install dependencies, create the database, run migrations, and build assets:

```sh
make setup
```

## Run

Start the Phoenix development server:

```sh
make server   # standard
make iex      # with IEx attached
```

The application is available at [http://localhost:4200](http://localhost:4200).

## Commands

| Command | Description |
|---------|-------------|
| `make infra` | Start PostgreSQL via Docker |
| `make setup` | Install deps, create DB, run migrations, build assets |
| `make server` | Start Phoenix dev server |
| `make iex` | Start Phoenix with IEx |
| `make fmt` | Format code |
| `make lint` | Format check + Credo strict + compile warnings-as-errors |
| `make test` | Run test suite |
| `make ci` | Lint then test (CI pipeline) |
| `make db.setup` | Create and migrate database |
| `make db.reset` | Drop, create, migrate, and seed database |
| `make db.migrate` | Run pending migrations |
| `make docs` | Generate HTML documentation to `priv/static/docs/` |

## Production

Build a release:

```sh
make release
```

Or build Docker images:

```sh
make docker.bundled   # single bundled image
make docker.build     # multi-image build (builder, base, app, seed)
```

Images are published to `ghcr.io/kakilangit/summoner`.
