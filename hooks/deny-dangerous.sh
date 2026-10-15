#!/usr/bin/env bash
set -uo pipefail   # never `-e`: a failing parse must fall through to allow, not crash

# Hook: deny-dangerous.sh (PreToolUse — Bash)
# Blocks catastrophic shell commands before they run. Patterns: hooks/lib/dangerous-patterns.txt.
# Exit 2 + reason on stderr = block (Claude Code hook contract). Anything else = allow.
#
# Why a hook and not a rule: the session runs in auto mode with the dangerous-mode prompt
# skipped, so nothing else stands between a model-proposed `rm -rf ~` and the disk.
# Guards against accidents, not a hostile agent — `python -c "shutil.rmtree(...)"` slips past.
# Adapted from github.com/davidondrej/skills (MIT).

PATTERNS="$(dirname "$0")/lib/dangerous-patterns.txt"
[ -f "$PATTERNS" ] || exit 0

CMD=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || true)
[ -n "$CMD" ] || exit 0

# One grep over all patterns on the hot path (allow); the per-pattern loop runs only to name the match.
ACTIVE=$(rg -v '^(#|$)' "$PATTERNS" 2>/dev/null || sed -e '/^#/d' -e '/^$/d' "$PATTERNS")
printf '%s\n' "$CMD" | grep -qE -f <(printf '%s\n' "$ACTIVE") 2>/dev/null || exit 0

while IFS= read -r pattern; do
  case "$pattern" in ''|\#*) continue ;; esac
  # grep -E here is the POSIX ERE engine the pattern file is written for; rule 005 governs agent searches, not hook internals.
  if printf '%s\n' "$CMD" | grep -qE -- "$pattern" 2>/dev/null; then
    echo "Blocked by deny-dangerous guard (context-forge hooks/lib/dangerous-patterns.txt). Matched: $pattern. Do not retry or work around it; tell the user — they can run it themselves with the ! prefix." >&2
    exit 2
  fi
done < "$PATTERNS"

exit 0
