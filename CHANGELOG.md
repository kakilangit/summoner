# Changelog

All notable changes to this project will be documented in this file.

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
