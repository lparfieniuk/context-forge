---
name: update-worklog
description: Appends a decision or phase-completion entry to the active ticket worklog. Use when a significant choice is made, never for routine steps.
model: haiku
---

## What This Does

Wraps `core/scripts/tools/worklog.sh`. Appends a single YAML entry to
`~/worklogs/tickets/<KEY>.yaml`. Performs skip-trigger validation before writing.
Auto-extracts PascalCase class names and camelCase method names from the scope field
and includes them in the `decisions` list for traceability.

## When to Use

**Trigger (MUST append):**
- Architectural or implementation decision made
- Phase or milestone completed
- Cross-boundary impact discovered
- Error root-caused

**SKIP triggers (do NOT append):**
- Simple file reads
- Clarifying questions
- Search operations (`rg`, `grep`, symbol lookup)
- Trivial edits under 5 lines

## How to Use

1. Confirm trigger condition is met (not a skip trigger).
2. Identify active ticket key from `~/worklogs/INDEX.yaml`.
3. Extract PascalCase class names and camelCase method names from the scope text.
4. Run: `bash core/scripts/tools/worklog.sh --key <KEY> --scope "<scope>" --ctx "<ctx>" --decisions "<d1>,<d2>"`
5. Verify entry is not a duplicate of the previous entry.

**Entry schema:**
```yaml
- ts: "YYYY-MM-DD HH:mm"
  repo: <repo-name>
  scope: <1-line description>
  ctx: <1-sentence why>
  decisions: [entity names, key choices]
```

## Output Format

```
[WORKLOG UPDATED]
- Ticket: PROJ-3456
- File: ~/worklogs/tickets/PROJ-3456.yaml
- Scope: chose ts-morph for code generation
- Entities extracted: [TsMorphFactory, generateCode]
[END WORKLOG UPDATED]
```

## Constraints

ALWAYS validate against skip triggers before appending.
NEVER append for trivial actions (reads, questions, searches, edits under 5 lines).
NEVER duplicate the previous entry — check last entry before writing.
ALWAYS auto-extract PascalCase class names and camelCase method names from scope.
ALWAYS keep scope to 1 line and ctx to 1 sentence.
NEVER write to the wrong ticket — always resolve active key from INDEX.yaml first.
