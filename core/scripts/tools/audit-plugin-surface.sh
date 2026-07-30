#!/usr/bin/env bash
# audit-plugin-surface.sh — validate plugin entrypoints, indexes, hooks, and surface claims.
#
# Usage:
#   bash core/scripts/tools/audit-plugin-surface.sh [--plugin-root <path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-root) PLUGIN_ROOT="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: audit-plugin-surface.sh [--plugin-root <path>]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

PLUGIN_ROOT="$(cd "$PLUGIN_ROOT" && pwd)"
INDEX="$PLUGIN_ROOT/core/_index.yaml"
SCRIPTS_INDEX="$PLUGIN_ROOT/core/scripts/_index.yaml"
TMPFILE="$(mktemp "${TMPDIR:-/tmp}/plugin-surface.XXXXXX")"
trap 'rm -f "$TMPFILE"' EXIT

fail() {
  echo "$1" >> "$TMPFILE"
}

count_section() {
  local section="$1"
  awk -v section="$section" '
    $0 == section ":" { active=1; next }
    active && /^[a-zA-Z_]+:/ { active=0 }
    active && /^  - id:/ { count++ }
    END { print count + 0 }
  ' "$INDEX"
}

has_index_id() {
  local file="$1"
  local id="$2"
  [[ -f "$file" ]] && rg -q "^  - id: ${id}$" "$file"
}

[[ -f "$PLUGIN_ROOT/package.json" ]] || fail "package.json missing"
if [[ -f "$PLUGIN_ROOT/package.json" ]] && ! rg -q '"test:audit"[[:space:]]*:' "$PLUGIN_ROOT/package.json"; then
  fail "package.json missing scripts.test:audit"
fi

for script_id in audit-runtime-artifacts audit-doc-claims audit-plugin-surface; do
  if ! has_index_id "$SCRIPTS_INDEX" "$script_id"; then
    fail "core/scripts/_index.yaml missing ${script_id}"
  fi
done

for skill_id in plugin-audit evolve; do
  if ! has_index_id "$INDEX" "$skill_id"; then
    fail "core/_index.yaml missing ${skill_id}"
  fi
done

if [[ -f "$PLUGIN_ROOT/hooks/hooks.json" ]]; then
  awk '
    /"command":/ {
      line=$0
      while (match(line, /hooks\/[A-Za-z0-9._-]+/)) {
        print substr(line, RSTART, RLENGTH)
        line=substr(line, RSTART + RLENGTH)
      }
    }
  ' "$PLUGIN_ROOT/hooks/hooks.json" | sort -u | while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    if [[ ! -f "$PLUGIN_ROOT/$rel" ]]; then
      fail "hook command target missing: $rel"
    fi
  done
else
  fail "hooks/hooks.json missing"
fi

if [[ -f "$INDEX" ]]; then
  AGENT_COUNT="$(count_section "agents")"
  DOC_EXPECTATIONS="$(mktemp "${TMPDIR:-/tmp}/agent-expectations.XXXXXX")"
  trap 'rm -f "$TMPFILE" "$DOC_EXPECTATIONS"' EXIT

  for rel in README.md CHANGELOG.md CLAUDE.md core/skills/help/SKILL.md skills/help/SKILL.md; do
    file="$PLUGIN_ROOT/$rel"
    [[ -f "$file" ]] || continue
    sed -nE 's/.*\*\*([0-9]+) agents?\*\*.*/\1/p; s/.*\(([0-9]+) agents?\).*/\1/p' "$file" >> "$DOC_EXPECTATIONS"
  done

  sort -u "$DOC_EXPECTATIONS" | while IFS= read -r expected; do
    [[ -z "$expected" ]] && continue
    if [[ "$expected" != "$AGENT_COUNT" ]]; then
      fail "agent count claim ${expected} != core/_index.yaml agents ${AGENT_COUNT}"
    fi
  done
else
  fail "core/_index.yaml missing"
fi

echo "[PLUGIN SURFACE AUDIT]"
echo "- plugin-root: $PLUGIN_ROOT"

if [[ -s "$TMPFILE" ]]; then
  echo "- surface: FAIL"
  sed 's/^/  - /' "$TMPFILE"
  echo "- final: FAIL"
  echo "[END PLUGIN SURFACE AUDIT]"
  exit 1
fi

echo "- surface: PASS"
echo "- final: PASS"
echo "[END PLUGIN SURFACE AUDIT]"
exit 0
