# Artifacts (Relics)

Artifacts are persistent outputs that outlive conversations — documents, code files, datasets, reports. They are versioned, shareable, and can be referenced across conversations.

## Agent Tools

All agents have three built-in artifact tools injected automatically:

| Tool | Description |
|------|-------------|
| `__create_artifact__` | Create a new artifact with name, type, content, and content type |
| `__update_artifact__` | Update an existing artifact (creates a new version) |
| `__read_artifact__` | Read an artifact by name or ID |

These tools are handled by the `CompositeToolExecutor` and do not need to be configured per agent.

## Versioning

Each update creates a new record with `version + 1` and `parent_id` pointing to the previous version. Lookup by workspace + name returns the latest version. The full version history is accessible on the show page.

## Pinning

Artifacts can be pinned to mark them as important. Pinned artifacts appear prominently in listings.

## Cross-Conversation References

Artifacts are scoped to workspaces, not conversations. Any agent in the same workspace can read or update an artifact created by another agent in a different conversation.

## UI

### Index Page (`/artifacts`)

Lists all artifacts in the workspace with search, sort by name/type/date, and pagination.

### Show Page (`/artifacts/:id`)

Displays artifact content with syntax highlighting (for code types), version history sidebar, and side-by-side version comparison.

### Dashboard

The workspace dashboard includes a Relics card showing recent artifacts. Conversations show a Relics button in the header for quick access to artifacts created during that conversation.

### Download

Artifacts can be exported/downloaded via the download controller at `/artifacts/:id/download`.
