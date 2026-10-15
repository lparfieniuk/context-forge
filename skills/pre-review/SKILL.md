---
name: pre-review
description: Gathers the diff, impact radius, and manifest freshness, then delegates to code review. Use when the user says "zrób review", "sprawdź moje zmiany", "przed commitem", "review my changes", "check this before I commit", "pre-review", or before a commit or merge request. Do NOT use to validate the plugin's own gates — that is plugin-audit; do NOT use on an empty diff.
model: haiku
---

## What This Does

Prepares the full context payload that `superpowers:requesting-code-review` needs to perform a
high-quality code review. This skill owns the **gather** phase; Superpowers owns the **review** phase.

**Delegation chain:**
```
/pre-review → gather context → package → superpowers:requesting-code-review → code-reviewer agent
```

### Gather phase (this skill):
1. `git diff --stat HEAD` — changed files with line counts
2. `git diff HEAD` — full diff (compressed via safe-exec if >5 KB)
3. Manifest freshness check: `ls -la <IDE_DIR>/shadow/**/_manifest.lightweight.yaml`
4. Impact radius analysis (see below)
5. Review marker — set LATER, not here: after the review returns and its findings are fixed, run
   `bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/review-marker.sh` in its own Bash call. It binds the marker
   to the working-tree fingerprint, so any edit after it blocks the commit until re-reviewed.

### Impact radius analysis:
- **If code-review-graph MCP is available:** call `detect_changes_tool` with changed file list,
  then `get_impact_radius_tool` to get importers and downstream consumers.
- **If MCP not available:** use `rg`-based heuristic — for each changed file, count importers:
  `rg -l "import.*from.*<filename>" --type ts | wc -l`

## When to Use

**Trigger:** Before any `git commit` or MR creation. Invoked manually via `/pre-review` or
automatically when the pre-commit-review hook fires.

**Skip:** NEVER skip — size of change does not exempt. Even 1-line changes require review.

## How to Use

1. Run `git diff --stat HEAD` to list changed files.
2. Run `git diff HEAD` — if output >5 KB, route through `safe-exec`.
3. Check manifest freshness; flag if stale.
4. Run impact radius analysis (MCP or rg-heuristic).
5. Package all context and invoke `superpowers:requesting-code-review`.
6. Fix the findings, then run `bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/review-marker.sh` in its own
   Bash call (the commit hook checks before the commit command runs).

## Output Format

```
[PRE-REVIEW]
- Changed files: 14
- Diff size: 2.3 KB (inline) | 47 KB (stored at ~/.claude/plugins/data/context-forge/logs/...)
- Manifest: FRESH | STALE (recommend /refresh-manifest before review)
- Impact radius: 23 importers (via code-review-graph MCP | rg heuristic)
- Review marker: set after findings are fixed (review-marker.sh)

Delegating to superpowers:requesting-code-review...
[END PRE-REVIEW]
```

## Constraints

NEVER perform the code review inline — ALWAYS delegate to `superpowers:requesting-code-review`.
ALWAYS set the review marker with `review-marker.sh` AFTER findings are fixed — NEVER with a bare `touch`, which records no content.
ALWAYS prefer code-review-graph MCP for impact radius over rg heuristic when available.
NEVER skip pre-review because the change seems small — size does not exempt.
ALWAYS compress diffs >5 KB through `safe-exec` before packaging context.
ALWAYS flag stale manifests in the context package so the reviewer is aware.
NEVER perform review inline using Read() + analysis — this is BANNED and is NOT a review.
