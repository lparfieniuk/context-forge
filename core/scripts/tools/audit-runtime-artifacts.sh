#!/usr/bin/env bash
# audit-runtime-artifacts.sh — detect runtime artifacts committed into plugin trees.
#
# Usage:
#   bash core/scripts/tools/audit-runtime-artifacts.sh [--plugin-root <path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-root) PLUGIN_ROOT="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: audit-runtime-artifacts.sh [--plugin-root <path>]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

PLUGIN_ROOT="$(cd "$PLUGIN_ROOT" && pwd)"
# The marketplace lives OUTSIDE the repo, as a sibling — same path convert.ts and
# hooks.test.ts use. Pointing at a child meant this scan silently never ran.
MARKETPLACE_ROOT="$PLUGIN_ROOT/../.local-marketplace/plugins/context-forge"
TMPFILE="$(mktemp "${TMPDIR:-/tmp}/runtime-artifacts.XXXXXX")"
trap 'rm -f "$TMPFILE"' EXIT

# Exempt an artifact only when git PROVES it can never ship: it is untracked AND
# ignored. This gate exists to keep runtime artifacts out of the published tree,
# so "does it exist" was the wrong test — rule 004 tells the agent to write failure
# ledgers to <IDE_DIR>/lessons/, which .gitignore has always excluded, so obeying
# rule 004 failed this gate and blocked commits. Untracked-but-NOT-ignored still
# fails: the audit runs before `git add`, which is exactly when a stray artifact is
# still untracked and most worth catching.
flag() {
  local root="$1" label="$2" in_git="$3" rel="$4"
  [[ -e "$root/$rel" ]] || return 0
  # Outside a git work tree (an installed/marketplace copy) nothing is tracked and
  # nothing is ignored, so existence is the only signal available there.
  if (( in_git )) \
     && [[ -z "$(git -C "$root" ls-files -- "$rel" 2>/dev/null)" ]] \
     && git -C "$root" check-ignore -q -- "$rel" 2>/dev/null; then
    return 0
  fi
  echo "$label/$rel" >> "$TMPFILE"
}

scan_root() {
  local root="$1"
  local label="$2"

  [[ -d "$root" ]] || return 0

  local in_git=0
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 && in_git=1

  for artifact in ".claude/cache" ".claude/lessons" ".cursor/lessons"; do
    flag "$root" "$label" "$in_git" "$artifact"
  done

  # Quote $root so it is stripped literally — an unquoted prefix is a glob pattern
  # and a root path containing [ ] would leave `rel` absolute and silently unmatched.
  while IFS= read -r path; do
    flag "$root" "$label" "$in_git" "${path#"$root"/}"
  done < <(find "$root" \
    \( -path "$root/.git" -o -path "$root/node_modules" \) -prune -o \
    \( -type f \( \
      -name "*observation*.log" -o \
      -name "*observation*.txt" -o \
      -name "*observation*.yaml" -o \
      -name "run-*.log" -o \
      -name "*-run.log" -o \
      -name "*.run.log" -o \
      -name "safe-exec-*.log" \
    \) -print \) 2>/dev/null)
}

scan_root "$PLUGIN_ROOT" "."
scan_root "$MARKETPLACE_ROOT" "../.local-marketplace/plugins/context-forge"

echo "[RUNTIME ARTIFACT AUDIT]"
echo "- plugin-root: $PLUGIN_ROOT"
if [[ -d "$MARKETPLACE_ROOT" ]]; then
  echo "- marketplace-root: present"
else
  echo "- marketplace-root: absent"
fi

if [[ -s "$TMPFILE" ]]; then
  echo "- runtime-artifacts: FAIL"
  sort -u "$TMPFILE" | sed 's/^/  - /'
  echo "- final: FAIL"
  echo "[END RUNTIME ARTIFACT AUDIT]"
  exit 1
fi

echo "- runtime-artifacts: PASS"
echo "- final: PASS"
echo "[END RUNTIME ARTIFACT AUDIT]"
exit 0
