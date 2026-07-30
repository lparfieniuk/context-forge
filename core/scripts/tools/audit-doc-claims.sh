#!/usr/bin/env bash
# audit-doc-claims.sh — verify active docs do not contain stale ContextForge claims.
#
# Usage:
#   bash core/scripts/tools/audit-doc-claims.sh [--plugin-root <path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-root) PLUGIN_ROOT="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: audit-doc-claims.sh [--plugin-root <path>]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

PLUGIN_ROOT="$(cd "$PLUGIN_ROOT" && pwd)"
INDEX="$PLUGIN_ROOT/core/_index.yaml"

if [[ ! -f "$INDEX" ]]; then
  echo "[DOC CLAIMS AUDIT]"
  echo "- index: FAIL (missing core/_index.yaml)"
  echo "- final: FAIL"
  echo "[END DOC CLAIMS AUDIT]"
  exit 1
fi

count_section() {
  local section="$1"
  awk -v section="$section" '
    $0 == section ":" { active=1; next }
    active && /^[a-zA-Z_]+:/ { active=0 }
    active && /^  - id:/ { count++ }
    END { print count + 0 }
  ' "$INDEX"
}

RULE_COUNT="$(count_section "rules")"
SKILL_COUNT="$(count_section "skills")"
AGENT_COUNT="$(count_section "agents")"
TMPFILE="$(mktemp "${TMPDIR:-/tmp}/doc-claims.XXXXXX")"
trap 'rm -f "$TMPFILE"' EXIT

DOCS="
README.md
CHANGELOG.md
CLAUDE.md
core/skills/help/SKILL.md
skills/help/SKILL.md
hooks/session-start.sh
"

record_failure() {
  local rel="$1"
  local line_no="$2"
  local reason="$3"
  local line="$4"

  printf '%s:%s: %s: %s\n' "$rel" "$line_no" "$reason" "$line" >> "$TMPFILE"
}

check_count_claim() {
  local rel="$1"
  local line_no="$2"
  local line="$3"
  local label="$4"
  local expected="$5"
  local found="$6"

  if [[ -n "$found" && "$found" != "$expected" ]]; then
    record_failure "$rel" "$line_no" "${label} count ${found} != ${expected}" "$line"
  fi
}

while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  file="$PLUGIN_ROOT/$rel"
  [[ -f "$file" ]] || continue

  line_no=0
  changelog_historical=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))

    if [[ "$rel" == "CHANGELOG.md" ]]; then
      if printf '%s\n' "$line" | rg -q '^## \[[0-9]'; then
        changelog_historical=1
      elif printf '%s\n' "$line" | rg -q '^## \[Unreleased\]'; then
        changelog_historical=0
      fi
    fi

    # Historical released CHANGELOG entries are frozen records of what shipped —
    # skip stale-token and count-claim validation for them (only [Unreleased]
    # and all other docs are checked against the current index counts).
    if [[ "$changelog_historical" -eq 1 ]]; then
      continue
    fi

    if printf '%s\n' "$line" | rg -q '(^|[^0-9])(12 rules|15 skills|2 agents)([^0-9]|$)|cf-router|\.claude/skills|\.cursor/skills|context_editing|tool_result_clearing|compact_20260112'; then
      record_failure "$rel" "$line_no" "stale token" "$line"
    fi

    rules_claim="$(printf '%s\n' "$line" | sed -nE 's/.*\*\*([0-9]+) rules\*\*.*/\1/p; s/.*\(([0-9]+) rules\).*/\1/p')"
    skills_claim="$(printf '%s\n' "$line" | sed -nE 's/.*all ([0-9]+) ContextForge skills.*/\1/p; s/.*ContextForge v[0-9.]+[^0-9]+([0-9]+) skills.*/\1/p; s/.*\*\*([0-9]+) skills\*\* across.*/\1/p; s/.*│.*\(([0-9]+) skills.*/\1/p')"
    agents_claim="$(printf '%s\n' "$line" | sed -nE 's/.*\*\*([0-9]+) agents?\*\*.*/\1/p; s/.*\(([0-9]+) agents?\).*/\1/p')"

    check_count_claim "$rel" "$line_no" "$line" "rules" "$RULE_COUNT" "$rules_claim"
    check_count_claim "$rel" "$line_no" "$line" "skills" "$SKILL_COUNT" "$skills_claim"
    check_count_claim "$rel" "$line_no" "$line" "agents" "$AGENT_COUNT" "$agents_claim"
  done < "$file"
done <<EOF
$DOCS
EOF

# Validate the plugin manifest description counts against the index/source of truth.
# Catches stale component claims (e.g. "4 agents" when there is 1) that the
# markdown count parser above does not cover.
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
if [[ -f "$PLUGIN_JSON" ]]; then
  PLUGIN_DESC="$(rg -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_JSON" | head -1)"
  HOOK_COUNT="$(find "$PLUGIN_ROOT/hooks" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | wc -l | tr -d ' ')"

  check_plugin_count() {
    local label="$1" actual="$2" claimed display
    display="${label/\?/}"
    claimed="$(printf '%s' "$PLUGIN_DESC" | sed -nE "s/.*[^0-9]([0-9]+) ${label}.*/\1/p")"
    if [[ -n "$claimed" && "$claimed" != "$actual" ]]; then
      record_failure ".claude-plugin/plugin.json" 4 "count mismatch" \
        "description claims ${claimed} ${display}, actual ${actual}"
    fi
  }

  check_plugin_count "rules" "$RULE_COUNT"
  check_plugin_count "skills" "$SKILL_COUNT"
  check_plugin_count "agents?" "$AGENT_COUNT"
  check_plugin_count "hooks" "$HOOK_COUNT"
fi

echo "[DOC CLAIMS AUDIT]"
echo "- plugin-root: $PLUGIN_ROOT"
echo "- index-counts: rules=$RULE_COUNT skills=$SKILL_COUNT agents=$AGENT_COUNT"

if [[ -s "$TMPFILE" ]]; then
  echo "- stale-claims: FAIL"
  sed 's/^/  - /' "$TMPFILE"
  echo "- final: FAIL"
  echo "[END DOC CLAIMS AUDIT]"
  exit 1
fi

echo "- stale-claims: PASS"
echo "- final: PASS"
echo "[END DOC CLAIMS AUDIT]"
exit 0
