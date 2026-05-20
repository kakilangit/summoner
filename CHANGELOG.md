# Changelog

All notable changes to this project will be documented in this file.

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

### Changed

- **Full DDD codebase restructure** — four-layer module naming convention
  - `Summoner.Domain.*` — schemas, events, policies, types
  - `Summoner.Ports.*` — behaviours and port interfaces
  - `Summoner.Adapters.*` — persistence, pubsub, workers, mailer, crypto
  - `Summoner.Services.*` — orchestration, inference, swarms, mcp, a2a, agents
- Pipeline runner dispatches by agent type (local via AgentServer, remote via A2A)
- Swarm runner dispatches by agent type with per-type timeout resolution
- Swarm round-robin passes last assistant message as context to remote agents
- `Broadcasts` module deleted — replaced by domain event structs
- LiveViews pattern-match on `%Domain.Events.*{}` structs in `handle_info`

### Fixed

- Mixed atom/string keys in `create_remote_agent` params
- Remote agent views guarded `@agent.local_agent.*` accesses for remote agents
- Stale moduledoc in `conversation_helpers.ex` updated from tuple to struct patterns
- Seeds file updated with renamed module references
- Enforced agent type constraints: orchestrated pipeline manager, directed swarm coordinator, and relay swarm members must be local agents
- Remote agents in round-robin swarms now receive the last assistant message as context instead of nil

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

[0.1.4]: https://github.com/kakilangit/summoner/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/kakilangit/summoner/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/kakilangit/summoner/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/kakilangit/summoner/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/kakilangit/summoner/releases/tag/v0.1.0
