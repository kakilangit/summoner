# Backup Agents & Failover

Summoner supports ordered failover chains so that when an agent fails, the system automatically retries with a backup agent. Failover is fully transparent to callers.

## How It Works

1. Each agent can have an ordered list of backup agents (the **failover chain**).
2. When an invocation fails with an eligible error (provider errors, timeouts, rate limits), the ReactLoop checks the failover chain.
3. If a backup agent is available, a new invocation is created with `failover_from_agent_id`, `failover_reason`, and `failover_depth` metadata. The original invocation is marked as `failed` with `end_reason: :failover`.
4. The caller receives the result from whichever agent eventually succeeds — failover is invisible.

## Eligible Errors

Not all errors trigger failover. The `FailoverPolicy` considers these eligible:

- Provider/inference errors (API failures, timeouts, rate limits)
- Context overflow
- Model not found

These do **not** trigger failover:

- Doom loop (agent stuck in a loop)
- User cancellation
- Approval rejection
- Hand-off to another agent

## Failover Chain

The chain is an ordered list stored in the `agent_failover_chain` join table with a `position` column. The system walks the chain in order, skipping any soft-deleted agents.

### Cycle Prevention

The `FailoverPolicy` validates that adding a backup agent does not create a cycle (A → B → C → A). Cycles are rejected at creation time.

### Depth Limit

Failover depth is tracked per chain of retries. The default maximum depth equals the chain length — an agent won't retry beyond its configured backups.

## UI

### Agent Edit Page

The failover chain is managed on the agent edit page with drag-and-drop reordering. Add backup agents from a dropdown of eligible agents (same workspace, not already in the chain, no cycles).

### Agent Show Page

The show page displays the failover chain as a read-only list with links to each backup agent and their model info.

### Failover Indicators

- **Agent cards** on the index page show a shield badge if the agent has backups configured.
- **Conversation view**, **swarm session view**, and **pipeline run view** display failover alerts when an invocation used a backup agent, showing the original agent, the backup used, and the reason.
- **Agent show page** displays failover stats: total failover count and last failover timestamp.
