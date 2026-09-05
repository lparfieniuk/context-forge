---
name: log-analyzer
description: Distills a build, test, or lint log into root cause, failing file and line, and a one-line fix. Use when the user says "why did the build fail", "analyse this log", "what broke", or pastes a long stack trace. Do NOT use for logs under 100 lines — read them directly; do NOT use for runtime application logs.
model: haiku
---

## What This Does

Runs `bash <CF_PLUGIN_ROOT>/core/scripts/tools/log-context-analyzer.sh --file <path>` to parse error logs using pattern matching for TypeScript, Jest, ESLint, Angular, and safe-exec observation formats. Uses contextual `rg` extraction and returns a structured RCA block with: root cause, failing file and line number when available, error message, and a 1-line fix suggestion. Never dumps raw log content into context.

## When to Use

- Build, test, or lint failure that needs root cause analysis
- safe-exec returned non-zero exit code with truncated output
- Error logs too large to read directly (>5 KB)
- Circuit breaker situation — need to understand failure before retrying

## How to Use

Step 1: Obtain the log file path (from safe-exec output or direct path).

Step 2: Run log-analyzer.

```bash
bash <CF_PLUGIN_ROOT>/core/scripts/tools/log-context-analyzer.sh --file <path/to/logfile>
```

Optional flags:
- `--log <path>` / `--log-file <path>` — backward-compatible aliases for `--file`
- `--format typescript|jest|eslint|build|generic` — alias for `--type`
- `--type typescript|jest|eslint|build|generic` — canonical format hint flag
- `--max-errors <n>` — limit to top N errors (default: 3)

Step 3: Apply the fix suggested in the RCA block. If the fix is ambiguous, use shadow-lookup to verify file paths before editing.

## Output Format

```
[RCA]
- Root cause: Missing export in barrel file
- Failing file: libs/billing/src/index.ts:10
- Error: TS2305 — Module has no exported member 'BillingFacade'
- Fix: Add `export { BillingFacade } from './lib/billing.facade';` to index.ts
[END RCA]
```

Each section is on its own line. Multiple errors produce multiple RCA blocks separated by a blank line.

## Constraints

- NEVER dump raw log content into context — always use this skill for extraction
- NEVER re-run the failed command without first applying the fix from the RCA block
- ALWAYS use the [RCA] envelope format — NEVER return freeform analysis
- ALWAYS pair with safe-exec: safe-exec captures output, log-analyzer extracts meaning
