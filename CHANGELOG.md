# Changelog

All notable changes to this project will be documented in this file.

## [0.1.16] - 2026-05-23

### Fixed

- Plugin container start crash when image not yet pulled — `run_detached` output contained pull progress instead of container ID
- Explicit `pull` before `docker run -d --pull never` ensures clean container ID output

## [0.1.15] - 2026-05-23

### Fixed

- Docker socket permission denied — added `group_add: ${DOCKER_GID:-0}` to bundled compose for host socket GID mapping

## [0.1.14] - 2026-05-23

### Fixed

- Docker container crash when docker CLI not available — `docker()` helper now rescues `ErlangError` gracefully
- `PluginContainerManager` made conditional via `:start_plugin_container_manager` config flag

### Changed

- Base image includes `docker-ce-cli` for plugin container management
- App container runs as `app` user in `docker` group (replaces `nobody`) for socket access
- Bundled compose mounts `/var/run/docker.sock` for plugin container management
- Bundled compose image and pull_policy parameterized via `SUMMONER_IMAGE` / `SUMMONER_PULL_POLICY` env vars

## [0.1.13] - 2026-05-22

### Changed

- **Plugin System v2 — Shared Container + HTTP**
  - Replaced stdio/MCP transport with bidirectional HTTP: Summoner calls plugin endpoints, plugins call Summoner's callback API
  - One container per unique image digest (shared across installations), config sent per-request
  - Container runtime uses Docker CLI adapter with health checks and auto-restart
  - `PluginContainerManager` manages container lifecycle under DynamicSupervisor with Registry-based lookup
  - `ProtocolHandler` bridges JSON-RPC for webhook, hook, event, models, and chat capabilities
  - `ContractValidator` policy for pure validation of plugin capability responses
  - `PluginWebhookController` for inbound webhooks at `POST /api/v1/plugins/:plugin_id/hook/:route`
  - `HookRunner` for lifecycle hooks (before/after invocation, on_tool_call, on_error) with circuit breaker
  - `PluginEventForwarder` subscribes to global PubSub and forwards domain events to plugins with `events` capability
  - `ActionExecutor` processes plugin actions (invoke_agent, invoke_agent_async, emit_event, log)
  - Container and state schemas for tracking container digests, ports, and status

- **OpenAPI Plugin Contract**
  - `plugin_contract.yaml` as single source of truth for the bidirectional HTTP contract
  - `EventSerializer` with explicit per-event serialization (replaces generic `Map.from_struct`)
  - Flattened `output.response`/`error` into top-level event fields

### Fixed

- Orphan sweep replaces grace-period container cleanup — strips version tag from container name so upgrades replace existing containers; health-check sweep removes containers whose digest has no enabled installations
- `external_ref` resolution uses `get_conversation_by_id` to find the external_ref (Slack channel) from Summoner's internal conversation_id
- `conversation_id` added to `InvocationStarted`, `InvocationCompleted`, `InvocationFailed` event structs and OpenAPI schemas

## [0.1.12] - 2026-05-22

### Added

- **RAG Pipeline (Codex)**
  - `knowledge_bases`, `knowledge_chunks`, `knowledge_base_agents` tables with pgvector IVFFlat cosine index
  - `KnowledgeBase` schema with type, chunking config, status, file hashes for change detection
  - `KnowledgeChunk` schema with pgvector embedding and virtual similarity field
  - `KnowledgeBaseAgent` join schema for agent-to-KB linking
  - Persistence ports and adapters for CRUD, agent linking, cosine search, and bulk insert
  - `DocumentParser` port with TXT, Markdown, HTML, PDF (pdftotext CLI), and DOCX (zip XML) adapters
  - `Chunker` service with three strategies: fixed-size, paragraph, semantic (all sentence-aware with overlap)
  - `IngestionWorker` Oban job: parse → chunk → batch embed → bulk insert → status update
  - `ReindexWorker` Oban job with incremental (single document) and full (all documents) modes
  - `__search_knowledge__` builtin tool for agents with linked knowledge bases
  - `CitationFormatter` policy for source annotations with `[N] [Source: ...]` markers
  - `RAG` service: search, format_for_prompt, ingest, reindex, document change detection
  - Knowledge context injected into agent system prompt alongside memories
  - File upload controller with 50MB limit, type validation, SHA-256 hashing
  - Knowledge base LiveViews: paginated index, create/edit form, detail page with document upload, search testing, agent linking
  - Codex card on workspace dashboard

## [0.1.11] - 2026-05-22

### Added

- **Plugin System (Grimoires)**
  - `plugin_installations` and `plugin_conversations` tables with indexes and constraints
  - `PluginInstallation` schema with capabilities array, status enum, manifest map, linked mcp_server_id/provider_id
  - `PluginConversation` schema for external_ref to conversation mapping with upsert
  - `ManifestValidator` policy — pure validation per capability (tools, webhooks, hooks, events, provider, theme)
  - Persistence port and adapter — CRUD, status transitions, capability filtering, conversation upsert
  - `:managed` transport option on `McpServer` for plugin-managed containers
  - `ContainerRuntime` port and Docker CLI adapter — pull, create, start, stop, rm, inspect, logs, extract_file
  - `PluginContainerManager` GenServer per plugin under DynamicSupervisor — health check (30s), auto-restart (max 3), Registry-based lookup
  - `ProtocolHandler` — JSON-RPC bridge for `summoner/webhook`, `summoner/hook`, `summoner/event`, `summoner/models`, `summoner/chat`
  - `ContractValidator` policy — pure validation of plugin capability responses
  - `PluginWebhookController` — inbound webhooks at `POST /api/v1/plugins/:plugin_id/hook/:route`
  - `HookRunner` — lifecycle hook runner (before/after invocation, on_tool_call, on_error) with circuit breaker
  - `PluginEventForwarder` — subscribes to global PubSub, forwards events to plugins with `events` capability
  - `ActionExecutor` — processes plugin actions (invoke_agent, invoke_agent_async, emit_event, log)
  - `PluginEvent` domain event struct for custom plugin events
  - `Plugins` service — install (pull → extract grimoire.json → validate → create), enable, disable, configure, upgrade, uninstall, handle_webhook, get_logs
  - Plugin LiveViews: index (paginated list, capability badges, status, enable/disable/uninstall), install (OCI image ref), show (config, manifest, container logs)
  - Grimoires card on workspace dashboard

### Changed

- `__remember__`, `__create_artifact__`, `__update_artifact__` tool descriptions widened to be context-agnostic (reference "task" not "user") for swarm and pipeline compatibility
- Agent show page nav links (Runes/Spellbook/Memories) moved before Instructions/Persona collapsibles

## [0.1.10] - 2026-05-22

### Added

- **Agent Memory**
  - `agent_memories` table with pgvector embeddings and IVFFlat cosine index
  - `AgentMemory` schema with type enum (fact, preference, procedure, correction), confidence, access tracking
  - `__remember__` builtin tool for agents to store memories during conversations
  - Shared embedding service resolves provider/model via `find_embedding_provider/1`
  - Memory context injected into agent system prompt before invocation
  - `MemoryDecay` policy — pure domain logic for interval-based exponential confidence decay
  - `MemoryDeduplication` policy — Jaro-Winkler string similarity + cosine vector dedup
  - `MemoryDecayWorker` — daily Oban cron (3:30 AM) applies decay, prunes below threshold, caps at 500/agent
  - `PartySharing` service — replicates fact/procedure memories to swarm peers at 0.7x confidence
  - Memory management LiveView at `/agents/:id/memories` with paginated list, type filter, sort, text search
  - Edit modal with content textarea and confidence slider; re-embeds async on content change
  - Bulk prune action to delete memories below a confidence threshold
  - Semantic search panel — embeds query and shows cosine similarity ranked results
  - `list_memories_paginated/2`, `update_embedding/2` port/adapter functions
  - 40 new tests: domain policies, decay worker, party sharing, LiveView

- **Artifact Markdown Rendering**
  - `text/markdown` artifacts rendered via Earmark instead of raw text
  - `relic-prose` CSS class for spacious document-style typography
  - Copy-to-clipboard button on artifact content (reuses CopyMessage hook)

### Fixed

- Footer version now reads from `Application.spec(:summoner, :vsn)` instead of hardcoded string

## [0.1.9] - 2026-05-22

### Added

- **MCP Server Mode**
  - Summoner exposes itself as an MCP server via Streamable HTTP transport at `/mcp`
  - 5 MCP tools: `invoke_agent`, `list_agents`, `run_pipeline`, `list_pipelines`, `search_skills`
  - Bearer token auth via `MCPAuth` plug — workspace derived from API access token
  - Stdio transport via `mix summoner.mcp.stdio` for local development
  - Config generator `mix summoner.mcp.config` outputs JSON for Claude Code, Cursor, etc.
  - Telemetry event: `[:summoner, :mcp, :session_started]`
  - Built on `anubis_mcp` server with compile-time component registration

- **CLI Tool (Rust)**
  - `summoner-cli/` — single-binary CLI wrapping the REST API
  - Commands: `agents list/show`, `invoke`, `chat` (interactive + one-shot), `pipelines list/runs`, `swarms list`, `completion`
  - TOML config with profiles (`~/.config/summoner/config.toml`)
  - Env var overrides: `SUMMONER_URL`, `SUMMONER_TOKEN`, `SUMMONER_WORKSPACE`, `SUMMONER_PROFILE`
  - Colored table output, JSON format mode, progress spinners
  - Stdin pipe support for `invoke` command
  - Shell completions for bash/zsh/fish

## [0.1.8] - 2026-05-22

### Added

- **Event Rules (Omens)**
  - `event_rules` and `event_rule_executions` tables with full audit trail
  - Declarative JSON condition DSL with `all`/`any`/`none` combinators and 10 operators (`eq`, `neq`, `in`, `contains`, `gt`, `lt`, `gte`, `lte`, `exists`, `matches`)
  - Nested field access in conditions (e.g. `agent.name`)
  - Four action types: `invoke_agent`, `run_pipeline`, `call_webhook`, `send_notification`
  - Template interpolation in action configs via `{{field.path}}`
  - Per-rule cooldown windows (0-86400 seconds)
  - Per-rule hourly rate limiting (`max_fires_per_hour`, 0 = unlimited)
  - Circuit breaker: auto-disables rules after 5 consecutive failures with exponential backoff
  - Telemetry events: `[:summoner, :event_rule, :evaluated]` and `[:summoner, :event_rule, :fired]`
  - Global PubSub scope — all domain events broadcast to `events:global` topic
  - `EventRuleEvaluator` GenServer subscribes once and dispatches via `Task.Supervisor`
  - REST API: CRUD + test endpoint + executions (`/api/v1/event-rules`)
  - LiveView UI: index (list with sort/filter/paginate, enable/disable toggle), form (new/edit with JSON editors for conditions and action config), show (detail view with paginated execution history)
  - Dry-run testing via API and UI

## [0.1.7] - 2026-05-22

### Added

- **Artifact System**
  - `artifacts` table with versioning via `parent_id` chain, soft-delete
  - Three agent tools: `__create_artifact__`, `__update_artifact__`, `__read_artifact__` injected into all agents
  - Artifacts routed through `CompositeToolExecutor`
  - Index page with search, sort, and pagination
  - Show page with content rendering, version history, and side-by-side comparison
  - Download controller for artifact export
  - Pinning toggle for important artifacts
  - Cross-conversation artifact references (lookup by workspace + name)
  - Relics card on workspace dashboard, Relics button in conversation header

- **Approval Flows**
  - `approval_rules` and `pending_approvals` tables
  - Three trigger types: `tool_call`, `cost_threshold`, `output_match`
  - `ApprovalCheck` pure policy for trigger evaluation
  - `ApprovalGate` service integrated into ReactLoop — pauses invocations when approval needed
  - Invocations transition to `awaiting_approval` status with `paused_at` and `paused_tool_call`
  - Rules CRUD UI (index, new, edit) with enable/disable toggle
  - Pending approvals list with inline approve/reject and decision notes
  - Oban `ApprovalTimeout` cron worker — auto-approve, reject, or escalate on timeout
  - Configurable timeout actions per rule
  - Rites card on workspace dashboard

## [0.1.6] - 2026-05-22

### Added

- **Backup Agents / Failover**
  - `agent_failover_chain` join table with ordered positions for failover chains
  - `FailoverPolicy` — pure policy: eligible error detection, cycle validation, chain walking
  - `AgentFailover` service — resolves backup agent from chain, skips deleted, respects max depth
  - ReactLoop integration — `maybe_failover_or_finish` transparently retries on eligible errors
  - Failover metadata on invocations: `failover_from_agent_id`, `failover_reason`, `failover_depth`
  - UI: drag-and-drop failover chain management on agent edit page
  - UI: failover chain display on agent show page with clickable links and model info
  - UI: failover alerts in conversation, swarm session, and pipeline run views
  - UI: failover chain indicator badges on agent cards in index page
  - Failover stats (count, last event) on agent show page

- **OpenAI-Compatible API**
  - `POST /v1/chat/completions` — non-streaming completions via `summoner:<callname>` model format
  - SSE streaming with `stream: true` — PubSub-driven OpenAI chunk format
  - Raw model access via `summoner:raw:<provider>/<model>` — direct Gateway inference
  - `GET /v1/models` — lists all agents and cached provider models in OpenAI format
  - Tool passthrough — `tools` from OpenAI request passed to Arcanum Intent
  - Multi-turn conversations via `X-Conversation-Id` header
  - `OpenAICompat` policy — pure formatting: `parse_model`, `extract_input`, `format_completion`, `format_chunk`, `format_error`
  - 19 unit tests for OpenAI formatter

### Changed

- Agent show page refactored to view-only (herald toggle, access_mode moved to edit form)
- Agent edit form widened to `max-w-2xl` with 2-column grid layouts
- Removed `max-w-*` constraints from all 23 LiveView pages for consistent full-width layout
- Sortable hook made configurable via `data-sortable-event` attribute

## [0.1.5] - 2026-05-21

### Added

- **REST API (Gates)**
  - Token-authenticated API with unified access token system (`shk_` prefix, 4 scopes: `a2a`, `api`, `admin`, `webhook`)
  - 12 CRUD controllers: Agent, Conversation, Pipeline, Swarm, Provider, Secret, McpServer, Skill, MediaProvider, Invocation, Usage, Admin
  - Flat API format: single resources returned as plain objects (no `data` wrapper), lists as `{items, meta}`
  - Pagination on all list endpoints (`page`, `per_page`, default 20, max 100)
  - `TokenAuth` and `RateLimit` plugs for API authentication and per-token rate limiting
  - Agent invocation via `POST /api/v1/agents/:id/invoke` (sync) and `POST /api/v1/agents/:id/stream` (SSE)
  - Invocation management: show, steps, events, cancel
  - Usage analytics: rolling 30-day stats and breakdowns
  - Admin endpoints: tenants, users, invitations, stats (requires `admin` scope)
  - OpenAPI 3.1 spec via `open_api_spex` — auto-generated from controller annotations
  - Swagger UI at `/dev/swaggerui`, spec at `GET /api/v1/openapi`
  - 60+ OpenAPI schema definitions in `SummonerWeb.API.Schemas`

- **Webhooks (Beacons)**
  - Webhook schema with target routing (agent/pipeline/swarm), auth modes (public/token/HMAC-SHA256), response modes (sync/async/stream)
  - CRUD API: `GET/POST/PUT/DELETE /api/v1/webhooks` (requires `api` scope)
  - Self-authenticated trigger: `POST /api/v1/webhooks/:id/trigger` (auth per webhook config)
  - `WebhookAuth` policy — pure HMAC-SHA256 verification (GitHub-compatible `X-Signature-256`)
  - `WebhookRateLimit` policy — per-webhook RPM limiting
  - `InputTransform` policy — `#{$.path.to.field}` template interpolation for payload transformation
  - `Services.Webhooks` orchestration: auth → rate limit → transform → route to target
  - SSE streaming support for webhook triggers
  - Domain events: `WebhookTriggered`, `WebhookFailed`

- **Access token delete** — tokens can be permanently deleted after revocation

### Changed

- **Route rename (breaking)**: All browser routes now use code names instead of display names
  - `/guilds` → `/tenants`, `/realms` → `/workspaces`, `/summons` → `/agents`
  - `/gateways` → `/providers`, `/channels` → `/conversations`, `/quests` → `/pipelines`
  - `/parties` → `/swarms`, `/runes` → `/mcp_servers`, `/spells` → `/skills`
  - `/seals` → `/secrets`, `/forges` → `/media_providers`, `/envoys` → `/remote_agents`
  - `/wards` → `/access_tokens`, `/scrolls` → `/files`, `/archon` → `/admin`
- **LiveView rename**: `WardLive.Index` → `AccessTokenLive.Index` (module and directory)
- **Naming convention**: Code names used in all code/files/routes/DB/API; display (fantasy) names used only in UI labels, titles, and breadcrumbs
- **Scope cleanup**: Removed `all`, `openai`, `mcp` scopes — final set: `a2a`, `api`, `admin`, `webhook`
- Updated all documentation to reflect new route paths

### Fixed

- **Access token list UI**: Replaced broken clickable-row pattern (`phx-click={JS.navigate}` on `<div>`) with standard non-clickable row + name-only link (consistent with agent/pipeline/swarm pages)
- **Revoke/Delete buttons**: Buttons now use standard `show_confirm` + `confirm_modal` pattern (same as all other pages)

## [0.1.4] - 2026-05-20

### Added

- **A2A protocol (Agent-to-Agent)**
  - Herald (A2A server) — workspace-scoped multi-token endpoint with access mode control
  - Envoy (A2A client) — outbound agent communication with bearer/API key auth
  - Agent card discovery, caching, and auto-refresh
  - A2A task tracking (inbound/outbound) with state lifecycle
  - Three-table agent split: `agents` + `local_agents` + `remote_agents`
  - Remote agents can now participate in pipelines and swarms
  - Skill-aware invocation: explicit skill per pipeline stage, inferred from agent card for conversations/swarms
  - `SkillResolver` — keyword-based skill inference from cached agent cards
  - `ClientExecutor` — raw JSON-RPC transport handling both Task and Message responses (works around upstream library limitation)
  - `pipeline_stages.skill` column for explicit A2A skill targeting
  - `INPUT_REQUIRED` handling — remote agents can request more input; continuation uses the same A2A task/context

- **Parallel tool execution**
  - `Summoner.Harness` module for concurrent tool call dispatch
  - Manager dispatch migrated to Harness

- **Domain event system**
  - 18 domain event structs under `Summoner.Domain.Events.*`
  - `Summoner.Ports.Events` port with compile-time adapter injection
  - `PubSubAdapter` with topic routing and fan-out (invocation events broadcast to both agent and invocation topics)
  - All publishers/subscribers migrated from raw tuples to struct-based pattern matching

- **Hexagonal architecture**
  - 18 persistence port behaviours (`Ports.Persistence.*/Adapter`) with `@callback` specs
  - 18 port delegation modules with `Application.compile_env` adapter injection
  - Worker port (`Ports.Workers`) decoupling from Oban
  - All services and web layer access persistence exclusively via ports

- **Agent icon component** — `hero-sparkles`/`bg-primary` for local agents, `hero-globe-alt`/`bg-secondary` for remote agents, with size and animation options

### Changed

- **Full DDD codebase restructure** — four-layer module naming convention
  - `Summoner.Domain.*` — schemas, events, policies, types
  - `Summoner.Ports.*` — behaviours and port interfaces
  - `Summoner.Adapters.*` — persistence, pubsub, workers, mailer, crypto
  - `Summoner.Services.*` — orchestration, inference, swarms, mcp, a2a, agents
- **Domain purity enforced** — `FailurePolicy` moved to `Services.Orchestration` (has side effects), `Content` accepts injected `file_reader:` option (no adapter import), `EncryptedBinary` moved to `Domain.Types`
- Pipeline runner dispatches by agent type (local via AgentServer, remote via A2A)
- Swarm runner dispatches by agent type with per-type timeout resolution
- Swarm round-robin passes last assistant message as context to remote agents
- Relay chain prompt rebalanced to encourage agent collaboration over premature `__done__`
- Model switcher disabled for remote agents (no local model selection)
- `Broadcasts` module deleted — replaced by domain event structs
- LiveViews pattern-match on `%Domain.Events.*{}` structs in `handle_info`
- Swarm mode labels deduplicated — shared `SwarmLive.Helpers` module (Circle/Chain/Command)

### Fixed

- Mixed atom/string keys in `create_remote_agent` params
- Remote agent views guarded `@agent.local_agent.*` accesses for remote agents
- Stale moduledoc in `conversation_helpers.ex` updated from tuple to struct patterns
- Seeds file updated with renamed module references
- Enforced agent type constraints: orchestrated pipeline manager, directed swarm coordinator, and relay swarm members must be local agents
- Remote agents in round-robin swarms now receive the last assistant message as context instead of nil
- **Auto-generated callnames never fail**: `unique_callname/2` queries existing callnames and appends `_2`, `_3`, etc. on conflict
- **Callname uniqueness errors surfaced in UI**: Both summon and envoy forms flash a user-facing error when callname constraint is violated
- **Bundled model changed to `qwen3:0.6b`**: Previous default `gemma3:1b` does not support tool use, causing HTTP 400 on all agent invocations
- **Ollama error messages visible**: Upgraded arcanum to 0.1.3 which drains async response bodies on streaming errors — error details now shown in invocation output instead of opaque struct
- **Soft-delete cascade cleanup**: Deleting an agent now removes its pipeline stages, swarm members, and conversation participants in a transaction
- **Soft-deleted agents blocked from execution**: `get_agent_with_provider!/1` filters by `deleted_at` — deleted agents can no longer be invoked
- **Soft-deleted agents rejected in validations**: Pipeline orchestrator, pipeline stages, swarm coordinator, and swarm member validations reject deleted agents
- **Conversations guard deleted agents**: Creating or switching to a deleted agent is rejected with a validation error; chat input disabled with error banner
- **Deleted agent badge in UI**: Conversation show page displays a "deleted" badge next to soft-deleted primary agents
- **CI: native multi-arch Docker builds**: Replaced QEMU emulation with native arm64 runners, extracted reusable `docker-build.yml` workflow, manifest creation uses `docker buildx imagetools`
- **Pipeline stage repositioning**: Removing a stage now compacts positions to avoid collisions when adding new stages
- **Pipeline stage agent change**: Stage detail form includes agent selector, allowing reassignment without recreating the stage
- **Add-stage form reset**: Form clears after successful submission instead of retaining stale values
- **Swarm conversation page crash**: `Conversations.Conversation` alias resolved to adapter module instead of schema — fixed to use `Domain.Schemas.Conversation`
- **Swarm relay chaining**: Agents now relay to other members instead of immediately calling `__done__` on first turn
- **Message edit UX**: Enter key submits the edit form (Save & Resend); Shift+Enter inserts a newline
- **Preload fix for pipeline stages**: `list_stages` now preloads `agent: [:local_agent, :remote_agent]` to avoid `Ecto.Association.NotLoaded` crashes

## [0.1.3] - 2026-05-19

### Added

- Standalone markdown documentation (`docs/`) with HTML generation via `make docs`
- SearXNG service in bundled Docker Compose for out-of-the-box web search

### Changed

- Documentation moved from in-app LiveView (`/dev/docs`) to standalone markdown files readable on GitHub
- SearXNG MCP preset default URL changed to `http://searxng:8080` (Docker bundled address)
- Removed Dev Docs nav link from application layout

## [0.1.2] - 2026-05-18

### Added

- `Summoner.Orchestration.ToolCallRecovery` module — recovers swarm signal tool calls (`__relay__`, `__done__`) that lose their name during streaming due to provider quirks
- Tests for tool call recovery (9 cases covering relay, done, and edge cases)
- Tests for `normalize_content/1` in SwarmCoordinator (3 cases)

### Fixed

- Swarm relay mode: agents now correctly hand off to the next member instead of terminating after one turn
- `find_done_call/1` now prefers relay calls with an actual agent target over ones signalling `"__done__"` when the model emits duplicate `__relay__` tool calls
- `normalize_content/1` in SwarmCoordinator — `Arcanum.Response.content` is a list of content blocks, not a plain string; extraction now handles both formats
- `__done__` from individual agents no longer terminates the entire swarm in relay/round_robin modes — only the coordinator (directed) or max_turns terminates
- `ToolCallRecovery` no longer infers `__complete__` from `"result"` arguments — the key is too ambiguous and caused false recoveries that broke provider API calls (HTTP 400)

### Changed

- Rename swarm modes to fantasy naming (Circle/Chain/Command)
- Naming consistency: guild/realm terminology throughout
- `copilot_client_id` now configurable via environment variable
- Removed debug loggers (coordinator raw response, swarm routing directive, full error body)

## [0.1.1] - 2026-05-18

### Changed

- Migrate Docker images from Docker Hub to GitHub Container Registry (`ghcr.io/kakilangit/summoner`)
- Bump `actions/checkout` and `actions/cache` to v5 (Node.js 24 compatibility)

## [0.1.0] - 2026-05-18

### Added

- Multi-workspace with role-based access (owner, admin, editor, operator, viewer)
- AI agent orchestration with ReAct loop, delegation, and tool use
- Provider support: Ollama, OpenAI, Anthropic, DeepSeek, xAI, OpenRouter, GitHub Copilot
- MCP server integration (stdio and SSE transports)
- Pipelines (sequential/orchestrated multi-agent workflows)
- Swarms (round-robin, relay, directed multi-agent collaboration)
- Media generation (images, video) via configurable media providers
- Skill system with vector embeddings (pgvector)
- Token usage tracking and cost budgeting
- Custom themes
- Release workflow with Docker image publishing and GitHub releases
- Pre-push hook to prevent direct pushes to main

### Fixed

- Replaced leftover HocusPocus references with Summoner

[0.1.16]: https://github.com/kakilangit/summoner/compare/v0.1.15...v0.1.16
[0.1.15]: https://github.com/kakilangit/summoner/compare/v0.1.14...v0.1.15
[0.1.14]: https://github.com/kakilangit/summoner/compare/v0.1.13...v0.1.14
[0.1.13]: https://github.com/kakilangit/summoner/compare/v0.1.12...v0.1.13
[0.1.12]: https://github.com/kakilangit/summoner/compare/v0.1.11...v0.1.12
[0.1.11]: https://github.com/kakilangit/summoner/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/kakilangit/summoner/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/kakilangit/summoner/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/kakilangit/summoner/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/kakilangit/summoner/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/kakilangit/summoner/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/kakilangit/summoner/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/kakilangit/summoner/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/kakilangit/summoner/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/kakilangit/summoner/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/kakilangit/summoner/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/kakilangit/summoner/releases/tag/v0.1.0
