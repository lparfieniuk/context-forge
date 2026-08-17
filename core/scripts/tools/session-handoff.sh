#!/usr/bin/env bash
# session-handoff.sh — emit the MECHANICAL half of a session handoff payload.
#
# Deterministic facts only (git + worklog tail). The judgment half — locked
# decisions, verified-vs-unverified, next step — is filled by the model that
# lived the session (see core/skills/session-handoff/SKILL.md). Splitting it
# this way keeps the expensive half small: the model writes ~15 lines, not 60.
#
# Usage: session-handoff.sh [--worklog <path>]
set -uo pipefail   # no -e: a handoff must never fail mid-emit

_WORKLOG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: session-handoff.sh [--worklog <path>]

Emit the deterministic half of a session handoff payload (markdown).

Options:
  --worklog <path>   — worklog YAML to tail (default: newest in ~/worklogs/tickets/)

Output: markdown block — branch, commits this session, dirty files, worklog tail.
EOF
      exit 0 ;;
    --worklog) _WORKLOG="${2:-}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not a git repository" >&2
  exit 1
fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
repo=$(basename "$(git rev-parse --show-toplevel)")

echo "## Handoff — ${repo} @ ${branch}"
echo
echo "### Repo state (deterministic)"
echo '```'
git log --oneline -5 2>/dev/null | sed 's/^/commit /'
git status --porcelain 2>/dev/null | head -20
echo '```'

# Files touched since the merge-base with the default branch — the real
# "what did this session ship" signal, wider than uncommitted-only.
base=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null || echo "")
if [[ -n "$base" && "$base" != "$(git rev-parse HEAD)" ]]; then
  echo
  echo "### Files changed vs merge-base"
  echo '```'
  git diff --stat "$base"...HEAD 2>/dev/null | tail -20
  echo '```'
fi

# Worklog tail — last 5 entries of the active ticket, if one exists.
if [[ -z "$_WORKLOG" ]]; then
  _WORKLOG=$(ls -t "$HOME"/worklogs/tickets/*.yaml 2>/dev/null | head -1)
fi
if [[ -n "$_WORKLOG" && -f "$_WORKLOG" ]]; then
  echo
  echo "### Worklog tail — $(basename "$_WORKLOG")"
  echo '```yaml'
  rg -n '^- ts:' "$_WORKLOG" 2>/dev/null | tail -5 | sed 's/^[0-9]*://'
  echo '```'
fi
