#!/usr/bin/env bash
set -uo pipefail   # never `-e`: a PostToolUse hook must not break the tool flow

# Hook: skill-usage-log.sh (PostToolUse, matcher Skill)
# Append-only record of every Skill invocation.
#
# Why a log at all when transcripts already hold this: Claude Code deletes
# transcripts after `cleanupPeriodDays` (default 30), so a transcript scan can
# only ever see a rolling month. This file is the history past that window.
#
# Format: TSV `ts<TAB>skill<TAB>repo` — one line, no dependencies beyond python3.

HOOK_JSON=$(cat)
SKILL=$(printf '%s' "$HOOK_JSON" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('skill', ''))
except Exception:
    pass
" 2>/dev/null || true)

[ -n "${SKILL:-}" ] || exit 0

LOG=~/worklogs/logs/skill-usage.tsv
mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0
printf '%s\t%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$SKILL" "$(basename "$PWD")" >> "$LOG" 2>/dev/null || true
exit 0
