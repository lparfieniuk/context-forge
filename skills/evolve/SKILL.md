---
name: evolve
description: >
  Runs the self-evolving loop v2 reviewer panel. Pre-filters signal, gates on
  Evidence, then spawns a Fit/Cost/Risk Haiku panel, and writes human-gated
  proposals (ADD/MODIFY/MERGE/PRUNE/REJECT) to <IDE_DIR>/evolve/pending/.
  NEVER edits rules or skills — proposals only.
  <example>
  Context: SessionStart showed "SELF-EVOLVE: 7 new signals — run /evolve".
  user: "/evolve"
  assistant: "[EVOLVE DIGEST] 2 proposals written to .claude/evolve/pending/ — human approval needed."
  </example>
model: sonnet
---

## What This Does

Synthesizes diaries + failure ledgers + learnings into vetted governance
proposals through a cost-sequenced 4-reviewer panel. Supersedes v1
`extract-lessons` and `self-learning-review`. NEVER auto-applies anything —
the human gate is non-negotiable.

## Cost-Sequenced Protocol

**Step 0 — Pre-filter (Tier 0).** Run `core/scripts/tools/evolve-signal.sh`.
If it prints `NO-SIGNAL`, STOP and emit `[EVOLVE] no signal (<n> new) — nothing to do`.
With `--dry-run`, continue using fixture inputs but do NOT spawn subagents.

**Step 1 — Evidence reviewer (Haiku, solo first).** Spawn ONE Task
(`model: "haiku"`) with the KERNEL prompt below to cluster the NEW signals into
candidate patterns, each with an occurrence count and a `PASS`/`NOISE` verdict.
If every pattern is `NOISE`, STOP and emit `[EVOLVE] all signal noise`.

**Step 2 — Fit / Cost / Risk panel (Haiku, one batch ≤ Tier 2 cap).** For the
`PASS` patterns only, spawn three Tasks (`model: "haiku"`), each ≤2000 tokens:
- **Fit:** verdict ∈ {ADD, MODIFY, MERGE, PRUNE, REJECT}, target rule/skill id.
- **Cost:** activation mode ∈ {always, intelligent, scoped}, always-on budget delta vs 6k.
- **Risk:** {OK, OVER-TRIGGERS, NEEDS-SCOPE, SELF-WEAKENING} + one-line justification.

**Step 3 — Aggregate (orchestrator, no extra subagent).** Combine the four
verdicts per pattern into a proposal. Drop any pattern where Fit=REJECT,
Risk=OVER-TRIGGERS, or Risk=SELF-WEAKENING (see Immutable Core). **Ledger dedupe (Tier 0):** before writing, check the
outcome ledger — `rg -c $'\t<verdict>\t<target>\t(reverted|reverted-patch)\t'
<IDE_DIR>/evolve/ledger.tsv`. If the same `verdict+target` was already reverted,
do NOT re-propose an identical patch: either drop it, or lower `confidence` and
annotate `pattern` with `(retry after prior revert)`. Write each surviving
proposal to `<IDE_DIR>/evolve/pending/<id>.yaml` (schema below). Then set
`last_processed_total` in `~/worklogs/diaries/INDEX.yaml` to the current total
signal count (so the next run only sees newer signal).

**Step 3a — Generate and verify patch_text (Tier 0, MANDATORY).** NEVER hand-write
a unified diff: `git apply` validates each hunk header's line counts against the
body, so a transcribed diff fails with `corrupt patch` and burns a `reverted-patch`
row. Produce every patch mechanically:

1. Copy the target file to a temp dir twice — `old` and `new` — and apply the
   intended edit to `new`. NEVER edit the real file under `core/`: an abort
   between edit and restore would leave a rule silently modified with no ledger
   row, violating this skill's own "NEVER apply a rule/skill" constraint. It also
   keeps the diff worktree-relative, which a HEAD-relative `git diff` is not once
   an earlier proposal in the same run is applied but still uncommitted.
2. `git diff --no-index -U3 <old> <new>`, then rewrite the temp paths in the
   `diff --git`, `---`, and `+++` lines to `a/<file>` / `b/<file>` and drop the
   `index` line.
3. Verify the RAW diff now, before indenting: pipe it to `git apply --check -`.
   A proposal whose patch fails `--check` is BANNED from `pending/`.
4. Only then indent 2 spaces into `patch_text`. The indent is storage formatting,
   NOT part of the patch — `git apply` rejects an indented diff with `No valid
   patches in input`, so anything re-verifying a stored proposal must strip it
   first (`sed 's/^  //' | git apply --check -`), exactly as `evolve-apply.sh` does.

Two proposals touching the same region of one file: apply the first, then
regenerate the second against the updated file.

**Step 4 — Emit digest.** Print the `[EVOLVE DIGEST]` envelope. If `--digest
<path>` was given, also write a markdown digest there. STOP. Await human review.

## KERNEL Prompts (rule 011 — Haiku, NO thinking params)

Evidence:
```
Context: ContextForge self-evolving loop — cluster signals into patterns.
Task: Read the diary/ledger/learning snippets provided and group them into
  distinct candidate patterns. For each, give an occurrence count and verdict.
Constraints: NEVER invent patterns unsupported by >=2 snippets. NEVER propose fixes here.
Format: Return [SUCCESS] + YAML list: [{pattern, count, verdict: PASS|NOISE}]. <=2000 tokens.
Verify: count of PASS patterns matches snippets cited.
```

Fit:
```
Context: Map one pattern to the existing 14 rules / 18 skills.
Task: Decide ADD | MODIFY | MERGE | PRUNE | REJECT and name the target rule/skill id.
Constraints: NEVER duplicate an existing constraint (that is MERGE). NEVER vague text.
Format: Return [SUCCESS] + {verdict, target, exact_constraint_text}. <=2000 tokens.
Verify: target id exists in core/_index.yaml (or "new").
```

Cost:
```
Context: Estimate token cost of adopting one proposed constraint.
Task: Recommend activation mode and the always-on budget delta vs the 6k target.
Constraints: NEVER recommend `always` for a constraint used <80% of sessions.
  Apply the simplicity criterion: an ADD with marginal benefit and a positive
  budget_delta is a REJECT candidate; a PRUNE/MERGE with a negative delta and
  equal-or-better coverage is favored. All else equal, simpler wins.
Format: Return [SUCCESS] + {activation, budget_delta_tokens, note}. <=2000 tokens.
Verify: budget_delta_tokens is a signed integer.
```

Risk:
```
Context: Devil's advocate on one proposed constraint.
Task: Judge false-positive / blast radius, then judge self-weakening.
Constraints: NEVER approve a constraint that blocks a legitimate common workflow.
  ALWAYS return SELF-WEAKENING when the target is in the Immutable Core, or when
  the patch only deletes/loosens a NEVER/BANNED line, a validation gate, or a
  human-approval step — regardless of how good the stated justification is.
Format: Return [SUCCESS] + {verdict: OK|OVER-TRIGGERS|NEEDS-SCOPE|SELF-WEAKENING, why}. <=2000 tokens.
Verify: why is one sentence.
```

## Immutable Core (never a proposal target)

A self-refining loop optimizes for the signal it is scored on, and the cheapest
way to stop producing failure signal is to remove the thing that reports it.
Prime Agent's `/refine` handles this by keeping the base system prompt immutable
while memories, skills and subagent specs stay rewritable; the same loop, run on
Factorio, refined its way into spawning resources through an admin console after
being told not to cheat. The human gate below is the review step, not the
boundary — these targets never reach it:

| Immutable target | Why |
|---|---|
| `core/rules/004-cf-circuit-breaker.*` | the halt itself — the loop must not file down its own brake |
| `core/skills/evolve/**`, `core/skills/evolve-apply/**` | this skill's own gate and apply path |
| `core/scripts/tools/plugin-audit.sh`, `audit-*.sh`, `evolve-apply.sh` | the audit that decides apply vs revert |

Everything else — rules, other skills, agents — stays a legitimate target.
Beyond the file list, the SHAPE is what disqualifies: a patch whose whole effect
is to delete a NEVER/BANNED line, drop a `## Validation gate` checkbox, or remove
a human-approval step is SELF-WEAKENING even on a mutable target. A constraint
that is genuinely wrong gets PRUNED by a human reading the proposal, not by the
loop quietly widening its own limits.

## Outcome Ledger (`<IDE_DIR>/evolve/ledger.tsv`)

Written by `evolve-apply.sh` — one tab-separated row per apply attempt (runtime
artifact, gitignored). Read it Tier-0 in Step 3 to avoid re-proposing reverted
patches (autoresearch `results.tsv` pattern: don't repeat discarded experiments).

```
ts	id	verdict	target	status	confidence
2026-07-03T11:04:00Z	abc12345	ADD	015-cf-mcp-tools	applied	0.82
2026-07-03T11:05:00Z	bad00001	MODIFY	003-cf-tier-routing	reverted-patch	0.55
```

`status` ∈ `applied | reverted | reverted-patch` (≈ keep | discard | crash).

## Proposal Schema (`<IDE_DIR>/evolve/pending/<id>.yaml`)

```yaml
id: <8-char id>
pattern: <synthesized pattern>
verdict: ADD|MODIFY|MERGE|PRUNE|REJECT
target: <rule id | skill id | "new">
patch_text: |
  <exact unified diff against core/rules/<file> or core/skills/<file>>
activation: always|intelligent|scoped
confidence: <0.0-1.0>
votes: {evidence: PASS, fit: <v>, cost: <v>, risk: <v>}
```

## Output Envelope

```
[EVOLVE DIGEST]
- New signals processed: <n>
- Proposals written: <m> → <IDE_DIR>/evolve/pending/
- <id> (<verdict> <target>, confidence <c>): <one-line pattern>
ACTION: Review each proposal; run /evolve-apply <id> to apply an approved one.
[END EVOLVE DIGEST]
```

## Constraints

NEVER edit any file under core/rules/ or core/skills/ — proposals only.
NEVER spawn the Fit/Cost/Risk batch before the Evidence gate returns PASS.
NEVER spawn more than 4 Haiku subagents per run; NEVER pass thinking params to Haiku.
ALWAYS advance last_processed_total only after proposals are written.
ALWAYS Tier-0 check ledger.tsv before writing a proposal; NEVER silently re-propose a reverted verdict+target.
ALWAYS generate patch_text from a real `git diff` and verify it with `git apply --check` before writing the proposal; hand-written hunk headers are BANNED.
ALWAYS include the ACTION footer (explicit human gate).
NEVER apply, merge, or delete a rule/skill — that is /evolve-apply, run by a human.
NEVER write a proposal targeting the Immutable Core, and NEVER write one whose only effect is deleting a NEVER/BANNED line, a validation gate, or a human-approval step.
