---
name: task-init
description: Creates a ticket worklog YAML and registers it in the worklog index. Use at the start of work on a new ticket.
model: haiku
---

## What This Does

Wraps `core/scripts/tools/task-init.sh`. Creates a standard worklog YAML for the given Jira key,
detects the current git branch, infers task type, and updates `~/worklogs/INDEX.yaml` with the
new active ticket.

## When to Use

**Trigger:** Starting work on a new Jira ticket (any key: PROJ-, ABC-, etc.).

**Skip:** Do NOT run if the ticket worklog already exists. Check INDEX.yaml first.

## How to Use

1. Extract Jira key from branch name or user message (e.g., `PROJ-3456`).
2. Run: `bash core/scripts/tools/task-init.sh --key <KEY>`
3. Script creates `~/worklogs/tickets/<KEY>.yaml` with schema: `key`, `scope`, `status`, `entries`.
4. Script appends entry to `~/worklogs/INDEX.yaml` under `active:`.
5. Return `[TASK INIT]` block.

## Output Format

```
[TASK INIT]
- Ticket: PROJ-3456
- Worklog: ~/worklogs/tickets/PROJ-3456.yaml
- Branch: feat/PROJ-3456-auth-refactor
- Task type: new_feature
- INDEX.yaml: updated
[END TASK INIT]
```

## Constraints

ALWAYS create worklog before starting any implementation work.
ALWAYS update INDEX.yaml — NEVER create ticket file without updating the index.
NEVER overwrite an existing ticket YAML — check for existence first.
NEVER invent Jira keys — extract from branch or ask the user.
