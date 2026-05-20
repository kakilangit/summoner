# Setup

After [installation](02-installation.md), the application needs initial data before it is usable. There are two approaches: seed setup for a quick start, or manual setup for full control.

## Seed Setup

The seed script creates the minimum required data to get started:

```sh
mix ecto.seed
# or
make db.reset   # drops, creates, migrates, and seeds
```

The seed performs two actions:

1. **Built-in themes** -- Seeds the default theme set (including `elixir-dark`).
2. **Admin user** -- If `ADMIN_EMAIL` and `ADMIN_PASSWORD` environment variables are set, creates an admin user with confirmed email and `role: "admin"`. Skips if the user already exists.

After seeding, log in at [http://localhost:4200](http://localhost:4200) with your admin credentials and proceed to create a Guild from the UI.

## Manual Setup

This section walks through each resource in the order they should be created.

### Guild

A **Guild** is the top-level tenant (organization). All users, workspaces, and shared resources belong to a guild.

**Create a guild:**

1. Navigate to **Guilds** in the top nav
2. Click **New Guild**
3. Enter a name (unique, 1-100 characters)

The creating user automatically becomes the guild **admin**. Guild admins can:

- Invite members via invitation codes
- Manage member roles (`admin` or `member`)
- Configure guild settings (registration mode, workspace/member limits, token quotas, budget caps)
- Manage guild-scoped resources (shared gateways, seals, runes, forges, spellbooks)

**Guild Settings:**

| Setting | Default | Description |
|---------|---------|-------------|
| Registration mode | Disabled | `disabled`, `invitation`, or `open` |
| Max workspaces | 10 | Limit per guild (1-10,000) |
| Max members | 50 | Limit per guild (1-100,000) |
| Monthly token quota | Unlimited | Optional cap on token usage |
| Monthly USD budget | Unlimited | Optional cap on spending |

### Realm

A **Realm** is a workspace within a guild. Each realm is an isolated environment with its own agents, conversations, providers, and files.

**Create a realm:**

1. From the guild page, navigate to **Realms**
2. Click **New Realm**
3. Enter a name (unique within the guild, 1-100 characters)

Each realm gets a data directory at `~/.summoner/workspaces/<realm_id>` for file storage.

**Realm roles:**

| Role | Permissions |
|------|-------------|
| Admin | Full control: settings, members, delete workspace |
| Member | Operate: run agents, create conversations, manage resources |
| Viewer | Read-only access |

**Realm Settings:**

| Setting | Default | Description |
|---------|---------|-------------|
| Context window messages | 20 | Messages sent to the model per inference call |
| Max tool output chars | 32,000 | Truncation limit for tool results |
| Harness | (default) | System prompt prefix prepended to all agents |
| Default step timeout | 60s | Per-step timeout (max 600s) |
| Default total timeout | 300s | Total invocation timeout (max 3,600s) |
| Monthly token quota | Unlimited | Optional cap |
| Monthly USD budget | Unlimited | Optional cap |

### Seal

A **Seal** is an encrypted secret (API key, token, password) stored with AES-256-GCM encryption at rest.

**Create a seal:**

1. Navigate to **Seals** (realm-scoped) or **Seals** under guild settings (guild-scoped)
2. Click **New Seal**
3. Enter a name (uppercase with underscores, e.g. `OPENAI_API_KEY`) and the secret value

**Key behaviors:**

- Referenced as `$SECRET_NAME` in MCP server environment configurations
- **Resolution precedence**: Realm-scoped seals override guild-scoped seals of the same name
- Cannot be deleted while MCP servers reference them
- Values are never displayed after creation

**Scope:**

- **Guild-scoped**: Shared across all realms in the guild
- **Realm-scoped**: Available only within that realm, overrides guild-scoped seals of the same name

### Gateway

A **Gateway** is an AI provider connection. Summoner supports multiple providers simultaneously.

**Create a gateway from a preset:**

1. Navigate to **Gateways**
2. Click **New Gateway**
3. Select a preset (e.g. OpenAI, Anthropic, Ollama)
4. The base URL and API format are auto-filled
5. Optionally link a Seal for the API key

**Available presets:**

| Preset | Base URL | API Format | Type |
|--------|----------|------------|------|
| Ollama | `http://localhost:11434` | Custom | Local |
| OpenAI | `https://api.openai.com/v1` | OpenAI | Cloud |
| Anthropic | `https://api.anthropic.com` | Anthropic | Cloud |
| DeepSeek | `https://api.deepseek.com` | OpenAI | Cloud |
| xAI | `https://api.x.ai/v1` | OpenAI | Cloud |
| OpenRouter | `https://openrouter.ai/api/v1` | OpenAI | Cloud |
| GitHub Copilot | `https://api.githubcopilot.com` | OpenAI | Cloud |
| Z.AI | `https://api.z.ai/api/coding/paas/v4` | OpenAI | Cloud |
| Custom | (user-defined) | OpenAI | Local |

**GitHub Copilot** uses an OAuth device code flow instead of an API key. Click "Connect" to initiate the flow and authorize via GitHub.

After creating a gateway, click **Refresh Models** to discover available models from the provider.

**Scope:** Gateways can be guild-scoped (shared) or realm-scoped (local).

### Summon

A **Summon** is an AI agent with a system prompt, personality, model selection, and tool access.

**Create a summon:**

1. Navigate to **Summons**
2. Click **New Summon**
3. Select a preset or configure manually:
   - **Name**: Display name (1-100 chars)
   - **Callname**: Auto-generated snake_case identifier (used for delegation and swarm routing)
   - **System prompt**: Instructions for the agent
   - **Personality**: Behavioral guidelines
   - **Gateway + Model**: Which provider and model to use
   - **Role**: `Autonomous` (independent, can delegate) or `Worker` (receives delegated tasks)

**Agent presets:** General Assistant, Code Wizard, Research Scholar, Creative Muse, Task Manager, Data Analyst, DevOps Engineer, First Principles Thinker, The Sceptic, Outside the Box.

**Configuration:**

| Setting | Default | Description |
|---------|---------|-------------|
| Max steps | 10 | ReAct loop iteration limit |
| Max concurrent invocations | 1 | Parallel execution limit |
| Max delegation concurrency | 3 | Parallel subtask limit |
| Max tokens per invocation | 50,000 | Token budget per run |
| Step timeout | 60s | Per-step timeout (max 600s) |
| Total timeout | 300s | Total invocation timeout (max 3,600s) |
| Budget (USD) | Unlimited | Optional cost cap |

**Agent links:** Autonomous agents can be linked to workers for delegation:

- **Delegate**: Manager sends a subtask; worker executes independently and returns the result
- **Handoff**: Manager transfers the conversation to the worker entirely

**Equipping tools and skills:**

- Navigate to a summon's **Runes** tab to equip/unequip MCP servers
- Navigate to the **Skills** tab to equip/unequip spellbook entries
- Only equipped tools are available to the agent during inference

### Channel

A **Channel** is a conversation between a user and one or more agents.

**Start a channel:**

1. Navigate to **Channels**
2. Click **New Channel**
3. Select an agent to start the conversation

**Channel types:**

| Type | Description |
|------|-------------|
| Chat | Standard conversation with a single agent (may delegate to workers) |
| Pipeline | System-created for quest execution |
| Swarm | Created via a party for multi-agent collaboration |

**Features:**

- Multimodal content: text, images, video
- Soft delete and restore for messages
- Message resend (deletes messages after a point and regenerates)
- Message editing with Enter to save and resend (Shift+Enter for newline)
- Conversation export as Markdown (up to 10,000 messages)
- Context compaction via summarization

### Quest

A **Quest** is a pipeline -- a multi-agent workflow with sequential or orchestrated execution.

**Create a quest:**

1. Navigate to **Quests**
2. Click **New Quest**
3. Choose a mode:
   - **Simple**: Stages run sequentially; each agent receives the previous stage's output
   - **Orchestrated**: A manager agent coordinates which stages run and when
4. Add stages: each stage has a position, an assigned agent, and an instruction
5. Optionally set a schedule (cron-based) for automatic execution

Existing stages can be edited: change the instruction, reassign the agent, or remove the stage. Removing a stage automatically repositions remaining stages to maintain contiguous ordering.

**Schedule presets:** Every 1/5/10/15/30 minutes, hourly, every 2/4/6/12 hours, daily at midnight/6AM/9AM/noon/6PM, weekly (Mon 9AM, Fri 5PM, weekdays, weekends), monthly (1st, 15th), or custom cron.

**Runs:**

Each quest execution creates a **Run** with per-stage tracking:

- Status: `pending` > `running` > `completed` / `failed` / `skipped`
- Input/output captured per stage
- Provider and model snapshot per stage
- Runs can be cancelled (cancels all pending stages and underlying invocations)

### Party

A **Party** is a swarm -- multi-agent collaboration where agents take turns contributing to a shared conversation.

**Create a party:**

1. Navigate to **Parties**
2. Click **New Party**
3. Choose a mode:
   - **Circle** (Round Robin): Agents take turns in fixed order
   - **Chain** (Relay): Agents hand off to the next via `__relay__` tool. Agents are encouraged to let others contribute before finishing.
   - **Command** (Directed): A coordinator agent decides who speaks next
4. Add members (up to 20 agents) and set their order
5. Set max turns (1-100, default 20)
6. For Command mode, select a coordinator agent

**Starting a party conversation:**

1. From the party page, navigate to **Channels**
2. Click **New Channel** -- all party members are added as participants
3. Send a message to begin the multi-agent conversation

### Supporting Resources

#### Rune (MCP Server)

A **Rune** is an MCP (Model Context Protocol) server that provides tools to agents.

**Create a rune:**

1. Navigate to **Runes**
2. Click **New Rune** or use the SearXNG preset
3. Configure:
   - **Transport**: `stdio` (command-line) or `http` (URL endpoint)
   - **Command/URL**: The command to run or URL to connect to
   - **Environment**: Key-value pairs, referencing seals via `$SECRET_NAME`

**Preset:** SearXNG (Web Search) -- `npx -y mcp-searxng` via stdio transport. Default `SEARXNG_URL` points to `http://searxng:8080` (the bundled Docker Compose address). Override this seal value if running SearXNG elsewhere.

Agents must explicitly have runes equipped (allowlist model). Each agent-rune binding can have per-agent environment overrides and can be individually enabled/disabled.

**Scope:** Guild-scoped (shared) or realm-scoped (local).

#### Forge (Media Provider)

A **Forge** is a media generation provider for images and video.

**Create a forge:**

1. Navigate to **Forges**
2. Click **New Forge**
3. Link an existing gateway (the forge uses the gateway's API connection)
4. Set default image and/or video models
5. Configure max concurrent generation jobs (default 3, max 10)

Agents can be linked to a specific forge, or fall back to the realm's default forge.

**Scope:** Guild-scoped (shared) or realm-scoped (local).

#### Spellbook (Skill)

A **Spellbook** entry is instructional content that can be equipped to agents. Skills support vector embeddings for semantic search via pgvector.

**Create a skill:**

1. Navigate to **Spellbooks**
2. Click **New Skill** or use a preset
3. Enter a name and content (instructions, reference material, guidelines)

**Skill presets:** Code Review, Technical Writer, SQL Expert, Testing Strategy, Content Creator.

Agents must have skills equipped. During inference, relevant skills are retrieved via cosine similarity search against the conversation context (max distance 0.5, top 5 results).

**Scope:** Guild-scoped (shared) or realm-scoped (local).
