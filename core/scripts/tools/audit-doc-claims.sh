#!/usr/bin/env bash
# audit-doc-claims.sh — verify active docs do not contain stale ContextForge claims.
#
# Also emits WARN lines for doctrine whose verification dates have aged past
# --staleness-days (default 60): rules carry dated claims ("verified 2026-07-21")
# precisely so they can be re-checked; without a gate the re-check never happens
# and the rule keeps asserting with confident tone long after its evidence rotted.
# WARN does not fail the gate — plugin-audit surfaces the count next to PASS.
#
# Usage:
#   bash core/scripts/tools/audit-doc-claims.sh [--plugin-root <path>] [--staleness-days <n>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
STALENESS_DAYS=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-root) PLUGIN_ROOT="$2"; shift 2 ;;
    --staleness-days) STALENESS_DAYS="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: audit-doc-claims.sh [--plugin-root <path>] [--staleness-days <n>]"
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
STALE_TMPFILE="$(mktemp "${TMPDIR:-/tmp}/doc-claims-stale.XXXXXX")"
TMPFILE="$(mktemp "${TMPDIR:-/tmp}/doc-claims.XXXXXX")"
trap 'rm -f "$TMPFILE" "$STALE_TMPFILE"' EXIT

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
HOOK_COUNT="$(find "$PLUGIN_ROOT/hooks" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | wc -l | tr -d ' ')"

check_plugin_count() {
  local label="$1" actual="$2" claimed display
  display="${label/\?/}"
  claimed="$(printf '%s' "$PLUGIN_DESC" | sed -nE "s/.*[^0-9]([0-9]+) ${label}.*/\1/p" | head -1)"
  if [[ -n "$claimed" && "$claimed" != "$actual" ]]; then
    record_failure "$MANIFEST_REL" 4 "count mismatch" \
      "description claims ${claimed} ${display}, actual ${actual}"
  fi
}

# Both manifests carry component counts in their descriptions; marketplace.json
# drifted unnoticed while only plugin.json was audited. All "description" values
# are concatenated because marketplace.json nests a second one under plugins[].
for MANIFEST_REL in ".claude-plugin/plugin.json" ".claude-plugin/marketplace.json"; do
  PLUGIN_JSON="$PLUGIN_ROOT/$MANIFEST_REL"
  [[ -f "$PLUGIN_JSON" ]] || continue
  # `rg` exits 1 on no match; under `set -euo pipefail` that killed the entire
  # audit silently (exit 1, zero output) on a manifest missing the key. Tolerate it.
  PLUGIN_DESC="$(rg -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_JSON" 2>/dev/null | tr '\n' ' ' || true)"

  check_plugin_count "rules" "$RULE_COUNT"
  check_plugin_count "skills" "$SKILL_COUNT"
  check_plugin_count "agents?" "$AGENT_COUNT"
  check_plugin_count "hooks" "$HOOK_COUNT"
done

# ---------------------------------------------------------------------------
# Version parity: plugin.json is the source of truth. Every other file that
# states the current version must agree. This drifted unnoticed across the 1.2.0
# bump — README's badge and CLAUDE.md still claimed 1.1.0 — because nothing
# compared them. Historical mentions (CHANGELOG entries, "1.1.0 was the first
# public cut") are NOT current-version claims and are deliberately not scanned.
# ---------------------------------------------------------------------------
CF_MANIFEST_VERSION="$(rg -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' \
  "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null \
  | head -1 | sed -E 's/.*"([^"]*)"$/\1/' || true)"

check_version_claim() {
  local rel="$1" pattern="$2" claimed
  [[ -f "$PLUGIN_ROOT/$rel" ]] || return 0
  claimed="$(rg -o -N "$pattern" "$PLUGIN_ROOT/$rel" 2>/dev/null \
    | head -1 | rg -o '[0-9]+\.[0-9]+\.[0-9]+' || true)"
  [[ -n "$claimed" ]] || return 0
  if [[ "$claimed" != "$CF_MANIFEST_VERSION" ]]; then
    record_failure "$rel" 1 "version drift" \
      "claims ${claimed}, plugin.json says ${CF_MANIFEST_VERSION}"
  fi
}

VERSION_FIELD='"version"[[:space:]]*:[[:space:]]*"[0-9.]+"'
if [[ -n "$CF_MANIFEST_VERSION" ]]; then
  # Manifests live in dot-directories, which plain `rg` skips by default — that is
  # exactly how .cursor-plugin/plugin.json sat at 1.1.0 unnoticed. Enumerate them.
  check_version_claim "package.json" "$VERSION_FIELD"
  check_version_claim ".claude-plugin/marketplace.json" "$VERSION_FIELD"
  check_version_claim ".cursor-plugin/plugin.json" "$VERSION_FIELD"
  check_version_claim "README.md" 'badge/version-[0-9.]+-'
  check_version_claim "CLAUDE.md" '\*\*Version:\*\*[[:space:]]*[0-9.]+'
else
  # Silence here would be the worst outcome: the gate whose whole job is policing
  # this file goes green precisely when this file is broken.
  echo "  - WARN: .claude-plugin/plugin.json version unreadable — version-drift checks SKIPPED"
fi

# ---------------------------------------------------------------------------
# Dated-claim staleness: rules must re-verify their evidence, not just carry it.
# Scans doctrine (core/rules/000–799; the gitignored 800–899 range is
# local-only and exempt) for verification dates and WARNs past the threshold.
# Historical records (ADRs, CHANGELOG) are exempt by design.
# ---------------------------------------------------------------------------

TODAY_ISO="$(date +%Y-%m-%d)"
stale_count=0

for rule_file in "$PLUGIN_ROOT"/core/rules/[0-7]*.md; do
  [[ -f "$rule_file" ]] || continue
  rel="core/rules/$(basename "$rule_file")"
  LC_ALL=C awk -v today="$TODAY_ISO" -v threshold="$STALENESS_DAYS" -v rel="$rel" '
    function days_from_civil(y, m, d) {
      y -= (m <= 2);
      era = int(y / 400);
      yoe = y - era * 400;
      doy = int((153 * (m + ((m > 2) ? -3 : 9)) + 2) / 5) + d - 1;
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy;
      return era * 146097 + doe - 719468;
    }
    {
      line = $0
      re = "(verified|measured|re-checked|checked)[^0-9]{0,40}[0-9]{4}-[0-9]{2}-[0-9]{2}"
      pos = match(line, re)
      while (pos > 0) {
        frag_len = RLENGTH
        frag = substr(line, pos, frag_len)
        match(frag, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)
        iso = substr(frag, RSTART, RLENGTH)
        split(iso, p, "-")
        age = days_from_civil(substr(today,1,4)+0, substr(today,6,2)+0, substr(today,9,2)+0) \
            - days_from_civil(p[1]+0, p[2]+0, p[3]+0)
        if (age > threshold + 0) {
          printf "WARN: %s:%d: %s verified %d days ago (> %s)\n", rel, NR, iso, age, threshold
        }
        line = substr(line, pos + frag_len)
        pos = match(line, re)
      }
    }
  ' "$rule_file" >> "$STALE_TMPFILE"
done

if [[ -s "$STALE_TMPFILE" ]]; then
  stale_count="$(wc -l < "$STALE_TMPFILE" | tr -d ' ')"
fi
sed 's/^/  /' "$STALE_TMPFILE"

echo "[DOC CLAIMS AUDIT]"
echo "- plugin-root: $PLUGIN_ROOT"
echo "- index-counts: rules=$RULE_COUNT skills=$SKILL_COUNT agents=$AGENT_COUNT"
echo "- dated-claims: ${stale_count} stale (>${STALENESS_DAYS}d), rest fresh"

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
