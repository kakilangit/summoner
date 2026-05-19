# Changelog

All notable changes to this project will be documented in this file.

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

[0.1.3]: https://github.com/kakilangit/summoner/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/kakilangit/summoner/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/kakilangit/summoner/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/kakilangit/summoner/releases/tag/v0.1.0
