# Changelog

All notable changes to this project will be documented in this file.

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

[0.1.1]: https://github.com/kakilangit/summoner/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/kakilangit/summoner/releases/tag/v0.1.0
