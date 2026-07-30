---
name: record-failure
description: >
  Creates a sharded failure ledger YAML at <IDE_DIR>/lessons/ when an unrecoverable error or
  circuit-breaker halt occurs. Checks for 3-strike patterns and auto-triggers /evolve.
  <example>
  Context: npm run build failed twice with the same TS error (circuit breaker triggered)
  user: "[CIRCUIT_BREAKER_HALT] — recording failure"
  assistant: "Written .claude/lessons/2026/04/14/a1/a1b2c3d4-barrel-export-missing.yaml"
  </example>
model: haiku
---

## What This Does

Wraps `core/scripts/tools/record-failure.sh`. Creates a minimalist YAML failure ledger with
exactly 3 semantic blocks: `execution_context`, `error_trajectory`, and `agent_reflection`.

After writing, checks if the same failure slug has occurred 3 or more times. If yes, triggers
the `/evolve` skill to surface patterns for human review.

**Sharding format:** `<IDE_DIR>/lessons/YYYY/MM/DD/<PREFIX>/<UUID>-<slug>.yaml`
where `<PREFIX>` is the first 2 characters of the UUID.

## When to Use

**Trigger (MANDATORY):**
- Circuit-breaker halt (`[CIRCUIT_BREAKER_HALT]` — same action failed twice)
- Unrecoverable error requiring human intervention
- Any degraded-state entry

**Skip:** Do NOT create a ledger for recoverable errors that were fixed on the first retry.

## How to Use

1. Generate a UUID and derive the 2-char prefix.
2. Create slug from 2-3 words describing the failure (e.g., `barrel-export-missing`).
3. Build sharded path: `<IDE_DIR>/lessons/YYYY/MM/DD/<PREFIX>/<UUID>-<slug>.yaml`
4. Write YAML with exactly 3 blocks (truncate `error_trajectory` to <500 chars).
5. Run 3-strike check: `find <IDE_DIR>/lessons/ -name "*<slug>*.yaml" | wc -l`
6. If count >= 3: invoke `/evolve` skill.

## Output Format

```yaml
# .claude/lessons/2026/04/14/a1/a1b2c3d4-barrel-export-missing.yaml
execution_context:
  goal: "Build billing module after adding cancelSubscription"
  tool: "Terminal (npm run build)"
error_trajectory: |
  libs/billing/src/index.ts:10:14 - error TS2305: Module has no exported member 'BillingFacade'.
  [TRUNCATED...]
agent_reflection: "Assumed BillingFacade was exported from index.ts because it existed in shadow
  index, but failed to verify barrel file. Must check barrel exports after adding new classes."
```

## Constraints

ALWAYS use time-series sharding `YYYY/MM/DD/PREFIX/UUID-slug.yaml` — NEVER flat directory.
ALWAYS include exactly 3 blocks: `execution_context`, `error_trajectory`, `agent_reflection`.
NEVER include more than 500 characters of raw stderr or stack traces in `error_trajectory`.
ALWAYS check 3-strike count after writing and trigger `/evolve` if count >= 3.
NEVER use JSON — ALWAYS use minimalist YAML.
NEVER skip failure logging when a circuit-breaker halt occurs.
