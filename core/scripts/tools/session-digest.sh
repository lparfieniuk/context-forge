#!/usr/bin/env bash
# session-digest.sh — between-session event digest + confidence-gate reminder.
#
# Surfaces the git working-tree delta so a resumed session starts where the last
# one left off (presence pattern), plus a one-line confidence gate: never claim
# "done" without test/build evidence (superpowers verification-before-completion).
# Deterministic, git-only, zero extra deps. Emits plain lines; the SessionStart
# hook wraps them under a header.

set -uo pipefail   # no `-e`: the digest must never break session startup

case "${1:-}" in
  --help|-h)
    cat <<'USAGE'
Usage: session-digest.sh

Between-session event digest: git working-tree delta, sync state, last commit,
and the confidence gate. Takes no arguments.
USAGE
    exit 0
    ;;
esac

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "not a git repository"
  echo "gate: claim \"done\" only with test/build evidence (verification-before-completion)"
  exit 0
fi

changed=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
staged=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

echo "changed: ${changed:-0} | staged: ${staged:-0} | untracked: ${untracked:-0}"

# Branch sync vs upstream, if one is configured.
if git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
  counts=$(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || echo "0	0")
  behind=$(echo "$counts" | awk '{print $1}')
  ahead=$(echo "$counts" | awk '{print $2}')
  echo "sync: ahead ${ahead:-0}, behind ${behind:-0}"
fi

last=$(git log -1 --format='%h %s' 2>/dev/null || true)
[ -n "$last" ] && echo "last: $last"

echo "gate: claim \"done\" only with test/build evidence (verification-before-completion)"
