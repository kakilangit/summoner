# Overview

Summoner is a local-first, multi-user, multi-workspace AI agent platform built with Elixir, Phoenix LiveView, and PostgreSQL.

## Core Concepts

Summoner uses fantasy-themed naming throughout the interface. Here is the mapping to standard terminology:

| Term | Meaning | Description |
|------|---------|-------------|
| **Guild** | Tenant / Organization | Top-level container for users, workspaces, and shared resources |
| **Realm** | Workspace | Isolated environment within a guild for agents, conversations, and workflows |
| **Seal** | Secret | Encrypted credential (API key, token) referenced by `$NAME` in configurations |
| **Gateway** | AI Provider | LLM provider connection (OpenAI, Anthropic, Ollama, etc.) |
| **Summon** | Agent | AI agent with a system prompt, personality, model, and tool access |
| **Channel** | Conversation | Chat session between a user and one or more agents |
| **Quest** | Pipeline | Sequential or orchestrated multi-agent workflow |
| **Party** | Swarm | Multi-agent collaboration (round-robin, relay, or directed) |
| **Rune** | MCP Server | Model Context Protocol server providing tools to agents |
| **Forge** | Media Provider | Image/video generation provider |
| **Spellbook** | Skill | Instructional content equipped to agents, searchable via vector embeddings |
| **Scroll** | File Browser | Workspace file manager |
| **Archon** | Admin Panel | System administration for users, tenants, and quotas |
| **Herald** | A2A Server | Inbound Agent-to-Agent protocol endpoint exposing local agents to external clients |
| **Envoy** | A2A Client / Remote Agent | Outbound connection to an external agent via A2A protocol |
| **Ward** | Access Token | Authentication token for API, webhooks, and Herald access |
| **Beacon** | Webhook | HTTP trigger that invokes agents from external systems (GitHub, CI/CD, etc.) |
| **Grimoire** | Plugin | OCI container extension with capabilities (tools, webhooks, hooks, events, provider, theme) |

## Architecture

- **Stack**: Elixir 1.19 / OTP 28 / Phoenix 1.8 (LiveView) / PostgreSQL 18 (pgvector) / Oban
- **Primary keys**: NULIDs (Crockford Base32), stored as `binary_id` (UUID) in PostgreSQL
- **Encryption**: AES-256-GCM via Cloak for secrets at rest
- **Multitenancy**: Two-level hierarchy -- Guilds (tenants) contain Realms (workspaces)
- **Scoping**: Resources are either guild-scoped (shared across all realms) or realm-scoped (local to one workspace). Realm-local resources override guild-shared ones of the same name.

### Hexagonal Layers

Summoner follows a four-layer hexagonal (ports and adapters) architecture:

```
Application (LiveViews, Controllers)
  |  calls services, subscribes to domain events
Domain (schemas, events, policies, types)
  -- pure data, no side effects
Ports (behaviours)
  -- contracts for side effects
Services (orchestration, inference, swarms)
  |  uses ports for side effects
Adapters (persistence, pubsub, workers, mailer, crypto)
     implements ports
```

| Layer | Namespace | Contents |
|-------|-----------|----------|
| Domain | `Summoner.Domain.*` | Ecto schemas, domain event structs, authorization policies, value types |
| Ports | `Summoner.Ports.*` | Behaviour definitions (`Events`, `Workers`, `Persistence.*`) with compile-time adapter injection |
| Adapters | `Summoner.Adapters.*` | Repo-backed persistence, PubSub, Oban workers, Cloak crypto, Swoosh mailer |
| Services | `Summoner.Services.*` | Orchestration (ReAct loop), inference, swarm coordination, MCP, A2A |

Domain logic never imports infrastructure modules. Services and LiveViews access persistence exclusively through port modules, not adapters directly.

## Supported Providers

| Provider | API Format | Type |
|----------|-----------|------|
| Ollama | Custom | Local |
| OpenAI | OpenAI | Cloud |
| Anthropic | Anthropic | Cloud |
| DeepSeek | OpenAI | Cloud |
| xAI | OpenAI | Cloud |
| OpenRouter | OpenAI | Cloud |
| GitHub Copilot | OpenAI | Cloud |
| Z.AI | OpenAI | Cloud |
| Custom | OpenAI | Local |

## Agent Orchestration

Agents use a **ReAct loop** (Reason + Act) for multi-step task execution:

1. Agent receives a prompt
2. Agent reasons about the next action
3. Agent calls tools (MCP servers, built-in tools, delegation)
4. Agent observes the result
5. Repeat until task completion or step limit

Agents can be **autonomous** (independent, can delegate to workers) or **workers** (receive delegated tasks, work in isolation).

## Multi-Agent Workflows

### Quests (Pipelines)

Sequential or orchestrated multi-agent workflows:

- **Simple mode**: Stages execute in order, each agent receiving the previous stage's output
- **Orchestrated mode**: A manager agent coordinates stage execution dynamically

### Parties (Swarms)

Multi-agent collaboration with three modes:

- **Circle** (Round Robin): Agents take turns in order, cycling until max turns
- **Chain** (Relay): Agents hand off to the next via structured routing (`__relay__` tool). Agents are encouraged to let other members contribute before signalling completion.
- **Command** (Directed): A coordinator agent decides who speaks next via JSON routing decisions

### Agent-to-Agent Protocol (A2A)

Summoner supports the [A2A protocol](https://github.com/google/A2A) for inter-agent communication across services.

**Herald (A2A Server):** Exposes local agents to external clients via a workspace-scoped JSON-RPC endpoint. Each Herald is configured with access mode (public or token-gated) and issues Wards (authentication tokens) for clients.

**Envoy (Remote Agent):** Connects to external A2A agents. Remote agents are registered with an agent card URL for discovery. Summoner caches the agent card (including skills) and refreshes it automatically.

**Skill-aware invocation:** Remote agents that advertise skills on their agent card can be invoked with explicit skill targeting (in pipelines via `pipeline_stages.skill`) or inferred skill matching (in conversations and swarms via keyword matching against skill names, descriptions, and tags).

**Remote agents in workflows:** Remote agents participate in pipelines and swarms alongside local agents. The pipeline runner and swarm runner dispatch by agent type, using A2A for remote agents and the local AgentServer for local agents. Orchestrated pipeline managers and directed swarm coordinators must be local agents. Relay swarm members must also be local (they need the `__relay__` handoff tool).
