---
name: pre-review
description: >
  Gathers code review context (git diff, changed files, manifest freshness, impact radius) and
  delegates to superpowers:requesting-code-review. Sets review marker to satisfy pre-commit hook.
  <example>
  Context: Feature implementation complete, about to commit
  user: "/pre-review"
  assistant: "Context gathered (14 files, impact radius 23). Delegating to superpowers:requesting-code-review."
  </example>
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
5. Set review marker. It MUST hash the **repo root**, not `$PWD` — `pre-commit-review.sh`
   normalizes via `git rev-parse --show-toplevel`, so a marker keyed to a subdirectory will
   not match (and `md5sum` alone does not exist on stock macOS; `echo` would add a newline):
   `touch /tmp/.claude-review-done-$(printf "%s" "$(git rev-parse --show-toplevel):$(whoami)" | (md5 -q 2>/dev/null || md5sum | awk '{print $1}') | cut -c1-8)`

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
5. Set review marker. It MUST hash the **repo root**, not `$PWD` — `pre-commit-review.sh`
   normalizes via `git rev-parse --show-toplevel`, so a marker keyed to a subdirectory will
   not match (and `md5sum` alone does not exist on stock macOS; `echo` would add a newline):
   `touch /tmp/.claude-review-done-$(printf "%s" "$(git rev-parse --show-toplevel):$(whoami)" | (md5 -q 2>/dev/null || md5sum | awk '{print $1}') | cut -c1-8)`
6. Package all context and invoke `superpowers:requesting-code-review`.

## Output Format

```
[PRE-REVIEW]
- Changed files: 14
- Diff size: 2.3 KB (inline) | 47 KB (stored at ~/.claude/plugins/data/context-forge/logs/...)
- Manifest: FRESH | STALE (recommend /refresh-manifest before review)
- Impact radius: 23 importers (via code-review-graph MCP | rg heuristic)
- Review marker: /tmp/.claude-review-done-a1b2c3d4 ✓

Delegating to superpowers:requesting-code-review...
[END PRE-REVIEW]
```

## Constraints

NEVER perform the code review inline — ALWAYS delegate to `superpowers:requesting-code-review`.
ALWAYS set the review marker at `/tmp/.claude-review-done-<hash>` before delegating.
ALWAYS prefer code-review-graph MCP for impact radius over rg heuristic when available.
NEVER skip pre-review because the change seems small — size does not exempt.
ALWAYS compress diffs >5 KB through `safe-exec` before packaging context.
ALWAYS flag stale manifests in the context package so the reviewer is aware.
NEVER perform review inline using Read() + analysis — this is BANNED and is NOT a review.
