# Kernel Prompts

## SYSTEM CONSTRAINTS

ALWAYS use KERNEL template structure for every Task() prompt.
NEVER spawn a Task() with a vague prompt lacking Context, Task, Constraints, Format, and Verify sections.
NEVER accept conversational filler back from subagents — mandate exact return format in prompt.
NEVER paste file contents, log bodies, or search dumps INTO a Task() prompt — ALWAYS pass paths, line ranges, or a query string and let the child read what it needs. A child's empty context is the entire reason delegating is cheaper than doing the work inline; a pasted payload spends that budget before the child has read its first instruction, and it is paid twice (once in the parent, once in the child).
NEVER spawn >2 concurrent Tier 3 Tasks without explicit authorization.
ALWAYS set `model: "haiku"` for Tier 2 tasks. NEVER use `model: "sonnet"` for Tier 2.
NEVER pass thinking parameters to `claude-haiku-4-5-20251001` — it does not support thinking.
When dispatching Tier 3 work via a direct Messages API call (SDK / your own orchestration), default to `output_config: {effort: "low"}` for Opus 4.8 unless deep reasoning is needed; `effort` lives in `output_config`, NEVER inside `thinking`. NOTE: Claude Code's Task/Agent tool does NOT expose `effort` or `thinking` — it manages subagent effort internally (default `xhigh`); for Task() the only routing lever is `model`.

## KERNEL Template (MANDATORY for all Task() prompts)

```
Context: <ticket key or brief goal, ≤1 sentence>
Task: <exact action to perform>
Constraints: NEVER [list hard constraints]
Format: Return [SUCCESS|FAILURE] + [required output format]
Verify: <rg or diff command to confirm change>
Done-when: <boolean condition a command can decide, no judgment>
```

## Done-when (deterministic termination gate)

`Verify:` names a command a human reads. `Done-when:` names a condition a SHELL decides — the parent evaluates it after the child returns, and a child claiming `[SUCCESS]` against a false `Done-when` is a FAILURE regardless of what it reported.

ALWAYS write `Done-when:` as a countable/existence predicate: file counts, non-empty checks, match counts, exit codes. NEVER as an adjective ("clean", "correct", "working", "good") — an adjective is a judgment the parent has to re-litigate, which is the bottleneck delegation was meant to remove.
ALWAYS evaluate `Done-when:` in the PARENT after the child returns — NEVER trust the child's own self-report as the gate. The child is the worker; the parent is the evaluator. Same separation as rule 004: a claim is not a measurement.
NEVER let a `Done-when:` predicate end in `tail`/`head`/`grep`/`echo` — the exit code belongs to that element, not the check (rule 004).
If `Done-when:` is false → this counts as ONE failure under rule 004. Re-dispatch once with the gap named, then halt. NEVER re-dispatch a third time.

| Bad `Done-when` | Why | Good `Done-when` |
|---|---|---|
| "tests pass" | ambiguous scope | `npm test 2>&1 \| tail -1` → exit 0 via `set -o pipefail` |
| "gtm docs written" | adjective | `[ $(find gtm -type f -size +1c \| wc -l) -ge 6 ]` |
| "competitors researched" | judgment | `[ $(rg -c "^## " gtm/competitors.md) -ge 6 ]` |
| "refactor complete" | unbounded | `rg -c "tenantId" src/auth/` = 12 |

## RED FLAG Table (Banned Prompt Patterns)

| RED FLAG | Why banned | Fix |
|----------|-----------|-----|
| "Do your best" | No success criteria | Add Format + Verify sections |
| "Fix the issue" | Vague task | Specify exact files + change |
| No Constraints section | Subagent may break APIs | Add NEVER constraints |
| No Format section | Filler pollutes context | Mandate `[SUCCESS]` prefix |
| No Verify section | No proof of correctness | Add rg/diff verification cmd |

## Scribe I/O Contract

When spawning Scribe for output masking, mandate this format:
```
[SCRIBE OUTPUT]
- Summary: <1 sentence>
- Key finding: <path:line or root cause>
- Recommendation: <1 sentence next action>
[END SCRIBE OUTPUT]
```

## Model-Specific Notes for Task() Prompts

| Model | Thinking support | KERNEL additions |
|-------|-----------------|-----------------|
| `claude-haiku-4-5-20251001` | None | No thinking params — omit entirely |
| `claude-sonnet-5` | Adaptive (`type: "adaptive"`, ON by default) — `budget_tokens` → 400 | Control depth with `output_config: {effort: "medium"}`; do NOT introduce `budget_tokens` |
| `claude-opus-4-8` | Adaptive (`type: "adaptive"`, OFF by default) | Set `thinking` explicitly; depth via `output_config: {effort: "low"}` (`"high"`/`"xhigh"` for architecture); `budget_tokens` → 400 |

NEVER pass a `thinking` param to Haiku subagents — Haiku 4.5 does not support thinking.
ALWAYS keep `output_config: {effort: "low"}` for cost-sensitive Opus subagents (`effort` is in `output_config`, never in `thinking`).

## Few-shot example

**Input:** "Refactor AuthService across 6 files — add tenantId to all methods."
**Reasoning:** >2 files, LLM judgment needed → Tier 2 (Haiku). Apply KERNEL template.
**Output:**
```
Task(
  subagent_type: "executor",
  model: "haiku",
  prompt: "Context: PROJ-3456 — add tenantId to AuthService. Task: Add tenantId parameter to all public methods in auth.service.ts, auth.facade.ts, auth.effects.ts, auth.actions.ts, billing.service.ts, api.ts. Constraints: NEVER change method return types; NEVER rename existing parameters. Format: Return [SUCCESS] + list of modified files. Verify: rg 'tenantId' src/auth/ shows 12 matches. Done-when: [ $(rg -c --no-filename tenantId src/auth/ | paste -sd+ | bc) -eq 12 ]"
)
```
Parent after return: run the `Done-when` predicate. False → one rule-004 strike, re-dispatch once naming the gap, then halt.

## Validation gate (MANDATORY before Task() spawn)

- [ ] KERNEL template used (Context / Task / Constraints / Format / Verify / Done-when)?
- [ ] `Done-when:` is a shell-decidable predicate (count/exists/exit code), not an adjective?
- [ ] Parent evaluates `Done-when:` after return — not trusting the child's `[SUCCESS]`?
- [ ] `model: "haiku"` for Tier 2 (not "default")?
- [ ] Format section mandates `[SUCCESS]` or `[FAILURE]` prefix?
- [ ] Verify section includes a runnable rg/diff command?
- [ ] Tier 3 concurrent count ≤2?
- [ ] If target model is Haiku: thinking params omitted from KERNEL?
- [ ] If target model is Opus 4.8: `thinking: {type: "adaptive"}` set explicitly and `effort` specified via `output_config` (default "low")?
If any unchecked → fix prompt before spawning.
