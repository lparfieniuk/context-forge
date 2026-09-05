---
name: safe-exec
description: Runs a shell command and compresses output over 5 KB to a log file plus a short summary. Use for builds, tests, installs, and migrations that would otherwise flood context — "run the build", "run the test suite", "npm install" on a noisy project. Do NOT use for quick commands whose output is small — plain Bash is cheaper and clearer.
model: haiku
---

## What This Does

Wraps command execution via `bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/safe-exec.sh -- <command>`. Captures stdout/stderr and checks output size. If output is ≤5 KB: returns full output inline. If output >5 KB: writes full output to `~/worklogs/logs/run_<timestamp>_<rand>.log` and returns a concise summary (<500 chars) with exit code and key error lines. Logs land in `~/worklogs/` — outside any project tree and any git repo, per rule 008-cf-worklog.

## When to Use

- Running any shell command expected to produce >5 KB output (build, test, lint)
- Preventing context bloat from large build logs or test result dumps
- Any command where failure root cause matters but full output would flood the context

## How to Use

```bash
bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/safe-exec.sh -- <command>
```

Examples:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/safe-exec.sh -- npm run build
bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/safe-exec.sh -- nx test billing
bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/safe-exec.sh -- ng lint
```

If exit code is non-zero and summary is insufficient for diagnosis, follow up with log-analyzer skill on the stored log file path.

## Output Format

```
[SAFE-EXEC]
- Command: npm run build
- Exit code: 1
- Output size: 47 KB (stored at ~/worklogs/logs/run_20260414_101530_a1b2c3d4.log)
- Summary: Build failed with 3 TypeScript errors in libs/billing/
- Key error: TS2305 — Module has no exported member 'BillingFacade'
[END SAFE-EXEC]
```

When output ≤5 KB, full output is returned instead of the envelope above.

## Constraints

- NEVER run large-output commands without this wrapper
- ALWAYS use the stored log path from the envelope for follow-up analysis with log-analyzer
- NEVER re-read the stored log directly into context — use log-analyzer skill instead
- ALWAYS treat non-zero exit code as a signal to invoke log-analyzer for RCA
