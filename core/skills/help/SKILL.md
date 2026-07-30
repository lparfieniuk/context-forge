---
name: help
description: >
  Lists all 20 ContextForge skills grouped by category, shows ownership and Superpowers
  delegation links, and reports current system status (manifests, worklogs, context capacity).
  <example>
  Context: Developer wants to know what skills are available
  user: "/help"
  assistant: "ContextForge 1.1.0 — 20 skills across 4 categories. System status: manifests FRESH, worklogs active."
  </example>
model: none
---

## What This Does

Renders a static capability reference listing all 20 ContextForge skills organized into 4
categories. No LLM processing required — this is a template response.

Also checks and reports:
- Shadow manifest freshness (`ls -la <IDE_DIR>/shadow/**/_manifest.lightweight.yaml`)
- Active worklog ticket count from `~/worklogs/INDEX.yaml`
- Current context capacity estimate

## When to Use

**Trigger:** `/help` command, "list skills", "what can you do", "available commands".

## How to Use

Return the template below, substituting live system status values.

## Output Format

```
ContextForge v1.1.0 — 20 skills, 4 categories

## Discovery (4 skills)
| Skill              | Tier | Ownership | Trigger |
|--------------------|------|-----------|---------|
| extract-signatures | 1    | OWNED     | "Extract signatures from file" |
| pack-context       | 2    | OWNED     | Task touches 3+ interrelated files |
| refresh-manifest   | 1    | OWNED     | Manifest missing or stale |
| shadow-lookup      | 0    | OWNED     | "Where is class X?" |

## Execution (4 skills)
| Skill         | Tier | Ownership | Trigger |
|---------------|------|-----------|---------|
| safe-exec     | 1    | OWNED     | Command expected to produce >5 KB output |
| log-analyzer  | 1    | OWNED     | Build/test/lint failure log |
| compile-wiki  | 2    | OWNED     | "/compile-wiki --domain <domain>" |
| clear-context | 1    | OWNED     | Tool results >30K tokens; before Tier 3 spawn |

## Workflow (9 skills)
| Skill             | Tier | Ownership | Trigger |
|-------------------|------|-----------|---------|
| task-init         | 1    | OWNED     | Starting new Jira task |
| update-worklog    | 1    | OWNED     | Decision made, phase completed |
| session-learnings | 2    | OWNED     | End of session |
| record-failure    | 1    | OWNED     | Unrecoverable error or circuit-breaker halt |
| diary             | 1    | OWNED     | Decision/outcome worth recording; /diary |
| evolve            | 3    | OWNED     | 3-strike pattern or manual /evolve |
| evolve-apply      | 1    | OWNED     | Human approved a pending /evolve proposal |
| pre-review        | 1    | DELEGATES | Before git commit or MR; /pre-review |
| end-session       | 1    | OWNED     | Session close-out; /end-session |

## Admin (3 skills)
| Skill          | Tier | Ownership | Trigger |
|----------------|------|-----------|---------|
| optimize-rules | 2    | OWNED     | /optimize-rules or token audit |
| plugin-audit   | 1    | OWNED     | /plugin-audit or plugin validation gate |
| help           | 0    | OWNED     | /help or "list skills" |

## Superpowers Delegation
pre-review → superpowers:requesting-code-review → code-reviewer agent

## System Status
- Manifests: [FRESH | STALE | MISSING] (check <IDE_DIR>/shadow/)
- Active worklogs: <count> tickets in ~/worklogs/INDEX.yaml
- Context capacity: ~<N>% used
```

## Constraints

ALWAYS list all 20 skills from `core/_index.yaml` — NEVER omit any skill.
ALWAYS show ownership column (OWNED vs DELEGATES).
NEVER require LLM processing — this is a static template with live status substitution.
ALWAYS include Superpowers delegation link for pre-review.
ALWAYS report system status (manifests, worklogs, capacity).
