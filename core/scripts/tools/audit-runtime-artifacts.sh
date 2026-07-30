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
MARKETPLACE_ROOT="$PLUGIN_ROOT/.local-marketplace/plugins/context-forge"
TMPFILE="$(mktemp "${TMPDIR:-/tmp}/runtime-artifacts.XXXXXX")"
trap 'rm -f "$TMPFILE"' EXIT

scan_root() {
  local root="$1"
  local label="$2"

  [[ -d "$root" ]] || return 0

  for artifact in ".claude/cache" ".claude/lessons" ".cursor/lessons"; do
    if [[ -e "$root/$artifact" ]]; then
      echo "$label/$artifact" >> "$TMPFILE"
    fi
  done

  find "$root" \
    \( -path "$root/.git" -o -path "$root/node_modules" \) -prune -o \
    \( -type f \( \
      -name "*observation*.log" -o \
      -name "*observation*.txt" -o \
      -name "*observation*.yaml" -o \
      -name "run-*.log" -o \
      -name "*-run.log" -o \
      -name "*.run.log" -o \
      -name "safe-exec-*.log" \
    \) -print \) 2>/dev/null | while IFS= read -r path; do
      rel="${path#$root/}"
      echo "$label/$rel" >> "$TMPFILE"
    done
}

scan_root "$PLUGIN_ROOT" "."
scan_root "$MARKETPLACE_ROOT" ".local-marketplace/plugins/context-forge"

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
