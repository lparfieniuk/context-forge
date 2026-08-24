---
name: failure-replay
description: Scaffolds a cf-bench regression case from a circuit-breaker failure ledger so a recorded incident becomes a replayable test case instead of prose. Use after record-failure when the failure was build/test/code-related.
model: haiku
---

## What This Does

Wraps `bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/failure-replay.sh --ledger <path>`. Reads a rule-004 failure ledger, classifies whether it is a reproducible code scenario (build/test/tooling signal in goal, tool, or error_trajectory), and for bench-replayable failures scaffolds a DRAFT case into cf-bench:

- `tasks/_drafts/replay-<slug>.task` — inert; the matrix glob never picks up `_drafts/`
- `fixtures/replay-<slug>/check.sh` — failing stub by design (exit 3)
- `fixtures/replay-<slug>/LEDGER.md` — ledger context extracted verbatim

For process-only failures (policy, workflow, tool behavior) it returns NOT REPLAYABLE with a reason and creates nothing.

## When to Use

- After `record-failure` wrote a ledger AND the failure involved code, a build, tests, or a tool command
- During `/evolve` review when a 3-strike pattern looks mechanically reproducible
- NEVER for recoverable first-retry fixes (no ledger exists — nothing to replay)

## How to Use

```bash
bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/failure-replay.sh --ledger <IDE_DIR>/lessons/YYYY/MM/DD/<prefix>/<uuid>-<slug>.yaml
```

Optional: `--bench-root <path>` (default `~/Projects/ai-tools/cf-bench`, overridable via `CFBENCH_ROOT`).

## Constraints

- NEVER promote a draft to `tasks/` before its `check.sh` is real — a stub that always fails proves nothing and validate-tasks.sh is not optional
- NEVER hand-edit the generated `.task` PROMPT to widen scope beyond the recorded failure — one incident, one case
- ALWAYS keep the fixture offline-runnable (bench rejects runs needing network)
- If the script says NOT REPLAYABLE, do NOT force a bench case — route the ledger into `/evolve` signal instead

## Output Format

```
[FAILURE-REPLAY]
- Verdict: REPLAYABLE | NOT REPLAYABLE (<reason>)
- Draft task: <path> (inert until promoted)
- Draft fixture: <path>
- Next: author fixture + real check.sh -> runner/validate-tasks.sh -> mv task out of _drafts/
[END FAILURE-REPLAY]
```

## Few-shot example

**Input:** Ledger `a1b2c3d4-barrel-export-missing.yaml`: goal "npm run build after adding cancelSubscription", error TS2305.
**Reasoning:** Build + TS error → bench-replayable. Scaffold, then a human authors the fixture.
**Output:**
```
[FAILURE-REPLAY]
- Verdict: REPLAYABLE
- Draft task: ~/Projects/ai-tools/cf-bench/tasks/_drafts/replay-barrel-export-missing.task (inert until promoted)
- Draft fixture: ~/Projects/ai-tools/cf-bench/fixtures/replay-barrel-export-missing/
- Next: author fixture + real check.sh -> runner/validate-tasks.sh -> mv task out of _drafts/
[END FAILURE-REPLAY]
```

## Validation gate (MANDATORY before reporting done)

- [ ] Ledger actually read this session (not recalled from memory)?
- [ ] Verdict quoted verbatim from the script output?
- [ ] If REPLAYABLE: author told that promotion requires a REAL check.sh + validate-tasks.sh?
- [ ] If NOT REPLAYABLE: no artifacts created, ledger routed to /evolve signal?
If any unchecked → fix before reporting.
