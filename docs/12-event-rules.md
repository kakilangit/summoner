# Event Rules (Omens)

Omens are declarative rules that react to domain events and trigger actions automatically. They turn Summoner from a request-driven platform into a reactive one.

## How It Works

1. Create an event rule specifying which event type to watch and what action to take.
2. When a matching domain event occurs, the `EventRuleEvaluator` checks conditions against the event payload.
3. If conditions match and the rule is not in cooldown or rate-limited, the action fires.
4. Every execution is recorded for audit.

## Event Types

Rules can subscribe to any of these domain events:

| Category | Events |
|----------|--------|
| Invocation | `invocation.started`, `invocation.completed`, `invocation.failed` |
| Pipeline | `pipeline.started`, `pipeline.completed`, `pipeline.failed` |
| Swarm | `swarm.turn`, `swarm.done`, `swarm.timeout` |
| Conversation | `conversation.message` |
| Webhook | `webhook.triggered`, `webhook.failed` |
| Approval | `approval.pending`, `approval.approved`, `approval.rejected`, `approval.expired` |
| Media | `media.started`, `media.completed`, `media.failed` |
| Copilot | `copilot.connected`, `copilot.failed` |
| Other | `failover`, `agent.config_changed` |

## Conditions

Conditions use a JSON DSL with combinators and operators. An empty condition object `{}` always matches.

### Combinators

- `all` — every sub-condition must match (AND)
- `any` — at least one must match (OR)
- `none` — none may match (NOR)

### Operators

| Operator | Description |
|----------|-------------|
| `eq` | Equal |
| `neq` | Not equal |
| `in` | Value is in a list |
| `contains` | String contains substring |
| `gt`, `lt`, `gte`, `lte` | Numeric comparisons |
| `exists` | Field is present and non-nil |
| `matches` | Regex match |

### Example

```json
{
  "all": [
    { "field": "event_type", "op": "eq", "value": "invocation.failed" },
    { "field": "agent.name", "op": "contains", "value": "prod" }
  ]
}
```

Nested field access is supported — `agent.name` traverses into the `agent` map.

## Action Types

| Type | Description | Required Config |
|------|-------------|-----------------|
| `invoke_agent` | Run an agent with a prompt | `agent_id` or `agent_callname`, `prompt` |
| `run_pipeline` | Start a pipeline run | `pipeline_id`, `input` |
| `call_webhook` | POST to an external URL | `url`, optional `headers` and `body` |
| `send_notification` | Log a notification | `message` (optional) |

### Template Interpolation

Action configs support `{{field.path}}` placeholders that are replaced with values from the event payload:

```json
{
  "agent_callname": "incident-handler",
  "prompt": "Agent {{agent.name}} failed: {{error}}"
}
```

## Hardening

### Cooldown

Each rule has a `cooldown_s` field (0–86400 seconds). After firing, the rule won't fire again until the cooldown expires. Set to `0` to disable.

### Rate Limiting

`max_fires_per_hour` caps how many times a rule can fire per hour. Set to `0` for unlimited.

### Circuit Breaker

After 5 consecutive failures, the rule is automatically disabled with exponential backoff (starting at 60 seconds, capped at 1 hour). The circuit resets on a successful execution.

## UI

### Rules List (`/event-rules`)

Lists all event rules with status badges, event type, action type, fire count, and enable/disable toggle.

### Create/Edit (`/event-rules/new`, `/event-rules/:id/edit`)

Form with JSON editors for conditions and action config, plus fields for event type, action type, cooldown, priority, rate limit, and enabled toggle.

### Detail (`/event-rules/:id`)

Shows rule configuration, conditions, action config, fire statistics, circuit breaker status, and a paginated list of past executions with status, latency, event snapshots, and action results.
