#!/usr/bin/env bash
# tools/review-marker.sh — record that the CURRENT working tree was reviewed.
# Usage: review-marker.sh [dir]
# Writes the worktree fingerprint to /tmp/.claude-review-done-<repo hash>; pre-commit-review.sh
# lets a commit through only while the tree still matches it. Run it AFTER review findings are
# fixed, in its own Bash call (the hook checks before the commit command runs).
set -euo pipefail
case "${1:-}" in --help|-h) sed -n 2,6p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib" && pwd)/common.sh"
DIR="${1:-$PWD}"
FP=$(worktree_fingerprint "$DIR") || { echo "error: not a git repo: $DIR" >&2; exit 2; }
MARKER="/tmp/.claude-review-done-$(repo_root_hash "$DIR")"
printf "%s\n" "$FP" > "$MARKER"
echo "review marker: $MARKER ($FP)"
