# Worklog

## SYSTEM CONSTRAINTS

ALWAYS externalize working memory to YAML scratchpads instead of relying on chat history.
ALWAYS read `~/worklogs/INDEX.yaml` at session start.
NEVER append a worklog entry for trivial actions (reads, searches, questions).
NEVER store worklogs inside any git repository.
ONLY append when: decision made, phase completed, cross-boundary impact found, or error root-caused.
ALWAYS practice observation masking: summarize large outputs immediately; discard raw text afterward.
ALWAYS set `supersedes: "<ts>"` on a new entry when it reverses or replaces an earlier decision.
NEVER edit or delete a superseded entry — the log is append-only; the backlink marks it historical, not the entry itself.
ALWAYS re-parse a structured worklog/index YAML after appending to it — a blind `cat >>` / `echo >>` append that produces invalid YAML fails silently and makes every later read return stale or zero data.

## Session Start Protocol

Step 1: Read `~/worklogs/INDEX.yaml`.
Step 2: If Jira key present → open `~/worklogs/tickets/<KEY>.yaml`. If entries >15 → return history_summary + last 5. Before treating any entry as current truth, scan the FULL file (not just the returned window) for a later entry's `supersedes` pointing at it — if found, treat it as historical only.
Step 3: Check ~/worklogs/learnings/INDEX.yaml for recent cross-session patterns (last 3 entries).
Step 4: If task is tooling/infrastructure → open relevant `ideas/` file.
Step 5: If not in INDEX → check `archive/` for legacy logs.

## Worklog Structure

```
~/worklogs/
  INDEX.yaml        — master index; read FIRST
  tickets/          — per-Jira worklogs (<KEY>.yaml)
  reports/          — audit/benchmark reports
  plans/            — architect plan files
  ideas/            — research & ideas
  analysis/         — UX/flow/technical analysis
  learnings/        — cross-session observations from /session-learnings (YYYY/MM/)
  archive/          — legacy files
  logs/             — safe-exec overflow logs (run_<timestamp>_<rand>.log), never in-repo
  wiki/             — compile-wiki output (Karpathy pattern: <domain>/index.md + concept pages)
```

## YAML Entry Format

```yaml
- ts: "YYYY-MM-DD HH:mm"
  scope: what changed
  ctx: why (one sentence)
  decisions: [key choices made]
  supersedes: "<ts of earlier entry, matching its `ts` format exactly>"   # optional, set only when this entry reverses/replaces that one
```

## Superseding Entries (staleness)

Worklogs are append-only, so a reversed decision must stay in the log — but a future reader (agent or human) has no way to know entry #3 was overturned by entry #7 without reading the whole file top to bottom. `supersedes` closes that gap with one field instead of a temporal-graph engine: it's a backlink, not a delete/invalidate operation.

- Set `supersedes` only when the new entry contradicts or overrides the decision in the prior entry — NEVER for incremental progress toward the same goal.
- At read time (Session Start Protocol Step 2 and any `/session-learnings` pass), scan for `supersedes` backlinks first — an entry pointed at by a later `supersedes` is historical context, not current truth.
- If multiple later entries `supersedes` the same target: the most recent backlink is current truth; the earlier ones are themselves historical record of how the decision changed over time.

## Few-shot example

**Input:** "I chose ts-morph for code generation instead of raw string templates." (Active: PROJ-3414)
**Reasoning:** Architectural decision → qualifies for worklog append.
**Output:**
```yaml
- ts: "2026-04-14 10:30"
  scope: code generation approach
  ctx: ts-morph provides AST-safe transforms vs error-prone string templates
  decisions: [use ts-morph for all code generation]
```

**Input:** "Actually, ts-morph's AST rewrite is too slow on the 400-file billing module — switching to string templates for that module only." (Active: PROJ-3414, reverses the 2026-04-14 10:30 entry)
**Reasoning:** Reverses a prior decision → append new entry AND backlink it via `supersedes`, don't touch the old entry.
**Output:**
```yaml
- ts: "2026-04-20 09:15"
  scope: code generation approach (billing module)
  ctx: ts-morph AST rewrite too slow on 400-file billing module
  decisions: [use string templates for billing module only; ts-morph elsewhere unchanged]
  supersedes: "2026-04-14 10:30"
```

## Validation gate (MANDATORY before appending)

- [ ] Is this a significant decision, completed phase, or cross-boundary discovery?
- [ ] Entry is one sentence (no paragraphs)?
- [ ] Does not duplicate the previous entry?
- [ ] Worklog file is outside any git repository?
- [ ] If this reverses/replaces an earlier decision: `supersedes` set to that entry's `ts`, and the old entry left untouched?
If any check fails → skip the append.
