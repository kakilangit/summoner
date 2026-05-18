.PHONY: setup server iex fmt lint test ci db.setup db.reset db.migrate release infra infra.up infra.down infra.logs docker.build docker.up docker.down docker.destroy docker.logs build.builder build.base build.app build.seed build hooks

## Git Hooks

hooks:
	git config core.hooksPath .githooks

## Infrastructure

infra: infra.up

infra.up:
	docker compose up -d --wait

infra.down:
	docker compose down

infra.logs:
	docker compose logs -f

## Development

setup: infra.up
	mix deps.get
	set -a && source .env && set +a && mix ecto.setup
	mix assets.setup
	mix assets.build

server:
	set -a && source .env && set +a && mix phx.server

iex:
	set -a && source .env && set +a && iex -S mix phx.server

## Quality

fmt:
	mix format

lint:
	mix format --check-formatted
	mix credo --strict
	mix compile --warnings-as-errors

test:
	mix test

ci: lint test

## Database

db.setup:
	mix ecto.create
	mix ecto.migrate
	set -a && source .env && set +a && mix run priv/repo/seeds.exs

db.reset:
	mix ecto.reset

db.migrate:
	mix ecto.migrate

## Release

release:
	MIX_ENV=prod mix release

## Docker (bundled — with Ollama + Gemma 3)

docker.build:
	docker compose -f docker-compose.bundled.yml build

docker.up:
	docker compose -f docker-compose.bundled.yml up -d

docker.down:
	docker compose -f docker-compose.bundled.yml down

docker.destroy:
	docker compose -f docker-compose.bundled.yml down -v

docker.logs:
	docker compose -f docker-compose.bundled.yml logs -f

## Docker images (local platform only)

DOCKER_IMAGE := ghcr.io/kakilangit/summoner
BUILDER_IMAGE := ghcr.io/kakilangit/summoner-builder
BASE_IMAGE := ghcr.io/kakilangit/summoner-base
SEED_IMAGE := ghcr.io/kakilangit/summoner-seed
DOCKER_TAG ?= latest

build.builder:
	docker pull $(BUILDER_IMAGE):$(DOCKER_TAG) 2>/dev/null || true
	docker build -f docker/builder/Dockerfile --cache-from $(BUILDER_IMAGE):$(DOCKER_TAG) -t $(BUILDER_IMAGE):$(DOCKER_TAG) .

build.base:
	docker pull $(BASE_IMAGE):$(DOCKER_TAG) 2>/dev/null || true
	docker build -f docker/base/Dockerfile --cache-from $(BASE_IMAGE):$(DOCKER_TAG) -t $(BASE_IMAGE):$(DOCKER_TAG) .

build.app:
	docker pull $(DOCKER_IMAGE):$(DOCKER_TAG) 2>/dev/null || true
	docker build --build-arg BUILDER_IMAGE=$(BUILDER_IMAGE):$(DOCKER_TAG) --build-arg BASE_IMAGE=$(BASE_IMAGE):$(DOCKER_TAG) --cache-from $(DOCKER_IMAGE):$(DOCKER_TAG) -t $(DOCKER_IMAGE):$(DOCKER_TAG) .

build.seed:
	docker pull $(SEED_IMAGE):$(DOCKER_TAG) 2>/dev/null || true
	docker build -f docker/seed/Dockerfile --cache-from $(SEED_IMAGE):$(DOCKER_TAG) -t $(SEED_IMAGE):$(DOCKER_TAG) .

build: build.builder build.base build.app build.seed
