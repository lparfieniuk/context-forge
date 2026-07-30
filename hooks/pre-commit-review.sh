#!/usr/bin/env bash
set -euo pipefail

# Hook 4: pre-commit-review.sh (PreToolUse — Bash)
# Block `git commit` without prior code review.

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# Read JSON input from stdin (Claude Code hook protocol)
HOOK_JSON=$(cat)
TOOL_INPUT=$(echo "$HOOK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Check if command contains "git commit"
if ! [[ "$TOOL_INPUT" =~ git[[:space:]]+commit ]]; then
  # Not a commit command, allow
  exit 0
fi

# Check for SKIP_REVIEW environment variable
if [ "${SKIP_REVIEW:-0}" == "1" ]; then
  exit 0
fi

# Generate session hash based on the command cwd and current user.
# PreToolUse hooks may execute from the plugin/runtime directory, while the
# Bash command itself runs in tool_input.cwd. Use the command cwd when present
# so the review marker matches the workspace being committed.
HOOK_CWD=$(echo "$HOOK_JSON" | python3 -c "import os,sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('cwd') or d.get('cwd') or os.environ.get('PWD',''))" 2>/dev/null || echo "$PWD")

# Normalize to the repo root: `cd subdir` inside the session must not invalidate a
# review done at the root (the hook runs BEFORE the command, so an inline `cd` in
# the commit command cannot help either).
if ! git -C "$HOOK_CWD" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "[BLOCKED] git commit from a path that is not a git repo (or no longer exists): $HOOK_CWD" >&2
  echo "REASON: cannot resolve the repo this commit belongs to, so the review marker cannot be checked." >&2
  exit 2
fi
SESSION_HASH=$(repo_root_hash "$HOOK_CWD")
REVIEW_MARKER="/tmp/.claude-review-done-${SESSION_HASH}"

# Check for review marker. Bounded by age: without this, one review at the start of a
# session silently unlocks every later commit in that repo forever.
REVIEW_TTL_MIN="${CF_REVIEW_TTL_MIN:-60}"
if [ -f "$REVIEW_MARKER" ]; then
  if [ -z "$(find "$REVIEW_MARKER" -mmin +"$REVIEW_TTL_MIN" 2>/dev/null)" ]; then
    exit 0
  fi
  rm -f "$REVIEW_MARKER"
  echo "[BLOCKED] review marker older than ${REVIEW_TTL_MIN} min — re-run /pre-review." >&2
  exit 2
fi

# No review marker found, block commit
cat >&2 << 'EOF'
[BLOCKED] git commit attempted without code review.
REASON: Code review required before commit (pre-commit-review hook + reviewer-protocol rule).

TO PROCEED:
  1. Use superpowers:requesting-code-review skill
  2. Wait for code-reviewer agent to complete review
  3. Review findings and address issues
  4. Try commit again

TO BYPASS (not recommended):
  SKIP_REVIEW=1 git commit -m "message"
EOF
exit 2
