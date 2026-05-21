# Approval Flows (Rites)

Approval flows add configurable checkpoints where agent actions pause for human review before executing. Critical for production use — agents should not perform destructive operations without explicit approval.

## Trigger Types

| Type | Description |
|------|-------------|
| `tool_call` | Pause when an agent attempts to call a specific tool (e.g., `bash`, `deploy`) |
| `cost_threshold` | Pause when estimated invocation cost exceeds a threshold |
| `output_match` | Pause when agent output matches a regex pattern |

## How It Works

1. Create an **approval rule** with a trigger type and configuration.
2. During agent execution, the `ApprovalGate` checks each tool call against enabled rules.
3. If a rule matches, the invocation transitions to `awaiting_approval` status.
4. The tool call is stored in `paused_tool_call` and the pause timestamp in `paused_at`.
5. A `PendingApproval` record is created with action details.
6. A human reviews and approves or rejects (with optional decision notes).
7. On approval, execution resumes. On rejection, the invocation fails with `approval_rejected`.

## Timeout Actions

Each rule can specify what happens if no decision is made within the timeout period:

| Action | Behavior |
|--------|----------|
| `approve` | Auto-approve and resume execution |
| `reject` | Auto-reject and fail the invocation |
| `escalate` | Mark as escalated for higher-level review |

The `ApprovalTimeout` Oban worker checks for expired approvals every minute.

## UI

### Rules Management (`/approval-rules`)

Create, edit, enable, and disable approval rules. Each rule specifies the trigger type, configuration, timeout duration, and timeout action.

### Pending Approvals (`/pending-approvals`)

Lists all pending approval requests with inline approve/reject buttons. Each entry shows the action summary, the agent and tool involved, and how long it has been waiting.

### Approval Detail (`/pending-approvals/:id`)

Full detail view with action details, tool call parameters, and a form for decision notes.

### Dashboard

The workspace dashboard includes a Rites card showing the count of pending approvals.
