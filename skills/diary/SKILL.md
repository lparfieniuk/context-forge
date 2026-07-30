---
name: diary
description: >
  Appends a decision/outcome entry to the current session's diary so the
  self-evolving loop learns from successes and failures, not just ledgers.
  Enriches the baseline entry written automatically at session end.
  <example>
  Context: Just chose count-based deltas over mtime math for portability.
  user: "/diary chose count-based signal delta — BSD find has no -newermt"
  assistant: "[DIARY] appended decision (outcome: worked) to today's diary entry."
  </example>
model: haiku
---

## What This Does

Records a single significant decision and its outcome into the current
session's diary entry. The diary is read later by `/evolve` alongside failure
ledgers and learnings. Captures **successes** (what worked) as well as
failures — the signal v1 never collected.

## When to Use

- A non-obvious decision was made (approach, tradeoff, tool choice).
- A pattern was confirmed to work, or a pattern failed.
- A phase completed with a reusable insight.

Do NOT use for trivial actions (reads, searches) — that is run-log noise.

## How to Use

1. Compute the session file path:
   - `hash = md5(PWD) | first 8 chars`, portable across macOS and Linux and byte-identical
     to `pwd_hash()` in `hooks/lib/common.sh` — the SessionEnd hook must land on the same file:
     `printf "%s" "$PWD" | (md5 -q 2>/dev/null || md5sum | awk '{print $1}') | cut -c1-8`.
     NEVER pipe `echo "$PWD"` here: it appends a newline and md5("path\n") is a different hash.
   - path = `~/worklogs/diaries/<YYYY>/<MM>/<YYYY-MM-DD>-<hash>.yaml`.
2. If the file does not exist, create it with `decisions:` as an empty block; the SessionEnd hook will append baseline keys later.
3. Append one list item under the correct key:
   - `decisions:` for a choice (`what`, `why`, `outcome: worked|failed|unknown`).
   - add the short pattern string to `worked:` or `failed:` when an outcome is known.
4. Keep each field to one sentence. NEVER paragraphs.
5. Emit `[DIARY] appended <key> to <path>`.

## Entry Shape (append, do not overwrite)

```yaml
decisions:
  - what: <choice made>
    why: <one sentence>
    outcome: worked
worked:
  - <short reusable pattern>
```

## Constraints

ALWAYS append — NEVER overwrite or reorder existing keys (the hook owns
`session/ts/task_type/branch/failed/signals`).
ALWAYS write to `~/worklogs/diaries/` — NEVER inside any git repo.
NEVER record trivial actions — only decisions, confirmed patterns, or failures.
ALWAYS keep each field to one sentence.
