---
name: safe-exec
description: >
  Runs a shell command with automatic output compression. If output exceeds 5 KB, writes full output to a timestamped log file and returns a concise summary. Prevents context bloat from large build/test/lint outputs.
  <example>
  Context: Running npm run build which produces large output.
  user: "Run npm run build and check for errors"
  assistant: "Running safe-exec for npm run build — output exceeding 5 KB will be stored and summarized."
  </example>
model: haiku
---

## What This Does

Wraps command execution via `bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/safe-exec.sh -- <command>`. Captures stdout/stderr and checks output size. If output is ≤5 KB: returns full output inline. If output >5 KB: writes full output to `~/worklogs/logs/run_<timestamp>_<rand>.log` and returns a concise summary (<500 chars) with exit code and key error lines. Never written inside the project tree — `${CLAUDE_PLUGIN_DATA}` is not a real Claude Code env var (only Codex/Copilot expose an equivalent); `~/worklogs/` is the same out-of-repo convention rule 008-cf-worklog already uses.

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
