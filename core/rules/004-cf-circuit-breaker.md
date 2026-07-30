# Circuit Breaker

## SYSTEM CONSTRAINTS

If same action fails twice: STOP immediately. Return `[CIRCUIT_BREAKER_HALT]` (see "Failure Response Chain" section below for output format).
NEVER attempt a third retry after the second failure of an identical action.
ALWAYS generate a Failure Ledger YAML on every circuit breaker halt.
On repeated failures: enter DEGRADED state — read-only tools only, escalate to human.
Failure ledger path: `<IDE_DIR>/lessons/YYYY/MM/DD/<2-char-prefix>/<UUID>-<slug>.yaml`
NEVER use JSON for failure logs. ALWAYS use minimalist YAML.
Error snippet MUST be truncated to <500 characters.
NEVER record a conclusion read off a log line as a measured fact — it is a HYPOTHESIS until a direct measurement reproduces it. ALWAYS keep `error_trajectory` raw and uninterpreted, and mark the inference as an assumption in `agent_reflection`.
NEVER infer success from a pipeline whose last element is `tail`, `echo`, `head`, or `grep` — the exit code belongs to that element, not to the command that matters. ALWAYS capture the real status (`set -o pipefail`, or `cmd; rc=$?`) before any transformation. A failure you cannot see is a strike the breaker cannot count.
NEVER treat a scripted in-place edit (`sed -i`, `awk`, `patch`) as applied because it exited 0 — a whitespace mismatch is a silent no-op indistinguishable from success. ALWAYS re-read or diff the target afterwards.
NEVER assume an external tool's output shape — it may ignore the filename you passed, drop sidecar files beside the real one, or write to stdout AND exit non-zero (GNU `stat -f`, which makes a `stat -f … || stat -c …` chain emit both). ALWAYS check what actually landed before consuming it.
ALWAYS extend the two-strike halt to metered work: after two identical failures against a paid resource (GPU pod, serverless worker, paid API), STOP and record cost-to-date instead of retrying.

## Failure Response Chain

1. **First failure** — log to failure ledger; attempt **bounded research escalation** (rule 016-cf-research-escalation: local-first, then routed GitHub-issue/docs research, Reddit/forum as lead-not-truth, ≤2 queries) to inform the fix; adjust approach, retry once. Record the research trace in the ledger.
2. **Second failure (same action)** — `[CIRCUIT_BREAKER_HALT]`, enter DEGRADED state (read-only).
3. **Third occurrence (across sessions)** — auto-trigger `/evolve` skill, draft rule suggestion.

## DEGRADED State

When DEGRADED is entered:
- All mutation tools (Write, Edit, Bash writes, git) are BLOCKED.
- Only read-only diagnostic tools permitted.
- Escalate to human operator before any further action.
- Exit DEGRADED only when human explicitly approves next step.

## Failure Ledger YAML Schema

```yaml
# <IDE_DIR>/lessons/YYYY/MM/DD/<prefix>/<UUID>-<slug>.yaml
execution_context:
  goal: "<what was being attempted>"
  tool: "<tool/command that failed>"
error_trajectory: |
  <stderr or error message — max 500 chars>
  [TRUNCATED...]
agent_reflection: "<root cause + false assumption that led to failure>"
cost_to_date: "<optional — set when the failed action was metered; e.g. '3.11 USD, 4 cold starts'>"
```

## 3-Strike Escalation (Cross-Session)

When the same failure slug appears 3+ times in `<IDE_DIR>/lessons/`:
1. Auto-trigger `/evolve` skill.
2. Skill reads ledgers, groups by pattern.
3. Drafts rule suggestion for human approval.
4. Human approves → `npm run convert` installs new rule.

## Few-shot example

**Input:** `npm run build` fails twice with "Module has no exported member 'BillingFacade'".
**Reasoning:** Same action failed twice → circuit breaker. Write ledger. Enter DEGRADED.
**Output:**
```yaml
# .claude/lessons/2026/04/14/f4/f47ac10b-billing-export-fail.yaml
execution_context:
  goal: "Build after adding cancelSubscription"
  tool: "Terminal (npm run build)"
error_trajectory: |
  billing.facade.ts:10:14 - error TS2305: Module has no exported member 'BillingFacade'.
  [TRUNCATED...]
agent_reflection: "Assumed BillingFacade exported from barrel; failed to verify index.ts exports."
```
Return: `[CIRCUIT_BREAKER_HALT]` — entering DEGRADED state. Human input required.

## Validation gate (MANDATORY before logging failure)

- [ ] File path uses sharding: `YYYY/MM/DD/<2-char-prefix>/<UUID>-<slug>.yaml`?
- [ ] YAML has the 3 required blocks: `execution_context`, `error_trajectory`, `agent_reflection` (plus optional `cost_to_date`)?
- [ ] Error snippet truncated to <500 chars?
- [ ] `agent_reflection` explains the false assumption (not just the error)?
- [ ] Exit status captured directly (not inferred from a trailing tail/echo/grep)?
- [ ] If the action was metered: `cost_to_date` recorded?
If any unchecked → fix before writing ledger.
