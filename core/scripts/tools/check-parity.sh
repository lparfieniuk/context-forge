#!/usr/bin/env bash
# check-parity.sh — Install Parity Check
#
# Compares core/ sources vs installed artifacts in skills/, agents/, .cursor/
# Adapted from ai-system's check_parity.sh for ContextForge plugin structure.
#
# Usage:
#   bash core/scripts/tools/check-parity.sh --plugin-root <path>
#
# Output:
#   DRIFT       — installed file differs from source
#   ORPHAN      — installed file has no corresponding source
#   NOT_INSTALLED — source exists but no installed counterpart
#
# Exit code: 0 always (informational only)

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: $(basename "$0") --plugin-root <path>"
  echo "  Compare core/ sources vs installed artifacts; detect drift and orphans"
  exit 0
fi

PLUGIN_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-root) PLUGIN_ROOT="$2"; shift 2 ;;
    # Legacy positional arg support
    *) PLUGIN_ROOT="$1"; shift ;;
  esac
done

if [[ -z "$PLUGIN_ROOT" ]]; then
  PLUGIN_ROOT="$(pwd)"
fi

DRIFT=0
ORPHANS=0
NOT_INSTALLED=0
INDEX_FILE="$PLUGIN_ROOT/core/_index.yaml"
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/check-parity.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

normalize_rule_content() {
  local file="$1"
  awk '
    NR == 1 && $0 == "---" { in_frontmatter=1; next }
    in_frontmatter && $0 == "---" { in_frontmatter=0; next }
    in_frontmatter { next }
    { sub(/[[:space:]]+$/, ""); print }
  ' "$file"
}

index_rules() {
  awk '
    function emit() {
      if (id != "") {
        printf "%s\t%s\t%s\t%s\n", id, source, installed_cursor, installed_claude
      }
    }
    /^rules:[[:space:]]*$/ { in_rules=1; next }
    in_rules && /^[^[:space:]][^:]*:/ { emit(); id=""; exit }
    in_rules && /^[[:space:]]*-[[:space:]]id:/ {
      emit()
      id=$3
      source=""
      installed_cursor=""
      installed_claude=""
      next
    }
    in_rules && /^[[:space:]]*source:/ { source=$2; next }
    in_rules && /^[[:space:]]*installed_cursor:/ { installed_cursor=$2; next }
    in_rules && /^[[:space:]]*installed_claude:/ { installed_claude=$2; next }
    END { emit() }
  ' "$INDEX_FILE"
}

echo "=== INSTALL PARITY CHECK ==="
echo "  plugin-root: $PLUGIN_ROOT"
echo ""

# ---------------------------------------------------------------------------
# Skills parity: core/skills/ vs skills/
# ---------------------------------------------------------------------------
echo "--- Skills ---"

SKILLS_INSTALLED="$PLUGIN_ROOT/skills"
SKILLS_SOURCE="$PLUGIN_ROOT/core/skills"

if [[ -d "$SKILLS_INSTALLED" ]]; then
  for installed in "$SKILLS_INSTALLED"/*/SKILL.md; do
    [[ -f "$installed" ]] || continue
    skill_name=$(basename "$(dirname "$installed")")
    source_file="$SKILLS_SOURCE/$skill_name/SKILL.md"

    if [[ ! -f "$source_file" ]]; then
      echo "  ORPHAN: skills/$skill_name/SKILL.md (no source in core/skills/)"
      ORPHANS=$((ORPHANS + 1))
    elif ! diff -qB "$source_file" "$installed" > /dev/null 2>&1; then
      echo "  DRIFT: core/skills/$skill_name/SKILL.md differs from skills/$skill_name/SKILL.md"
      DRIFT=$((DRIFT + 1))
    fi
  done
fi

if [[ -d "$SKILLS_SOURCE" ]]; then
  for source_dir in "$SKILLS_SOURCE"/*/; do
    [[ -d "$source_dir" ]] || continue
    skill_name=$(basename "$source_dir")
    if [[ ! -f "$SKILLS_INSTALLED/$skill_name/SKILL.md" ]]; then
      echo "  NOT_INSTALLED: core/skills/$skill_name/ missing from skills/"
      NOT_INSTALLED=$((NOT_INSTALLED + 1))
    fi
  done
fi

# ---------------------------------------------------------------------------
# Agents parity: core/agents/ vs agents/ and .cursor/agents/
# ---------------------------------------------------------------------------
echo ""
echo "--- Agents ---"

for ide_dir in "agents" ".cursor/agents"; do
  IDE_AGENTS="$PLUGIN_ROOT/$ide_dir"
  AGENTS_SOURCE="$PLUGIN_ROOT/core/agents"

  if [[ -d "$IDE_AGENTS" ]]; then
    for installed in "$IDE_AGENTS"/*.md; do
      [[ -f "$installed" ]] || continue
      fname=$(basename "$installed")
      source_file="$AGENTS_SOURCE/$fname"

      if [[ ! -f "$source_file" ]]; then
        echo "  ORPHAN: $ide_dir/$fname (no source in core/agents/)"
        ORPHANS=$((ORPHANS + 1))
      elif ! diff -qB "$source_file" "$installed" > /dev/null 2>&1; then
        echo "  DRIFT: core/agents/$fname differs from $ide_dir/$fname"
        DRIFT=$((DRIFT + 1))
      fi
    done
  fi
done

if [[ -d "$PLUGIN_ROOT/core/agents" ]]; then
  for source_file in "$PLUGIN_ROOT/core/agents"/*.md; do
    [[ -f "$source_file" ]] || continue
    fname=$(basename "$source_file")
    if [[ ! -f "$PLUGIN_ROOT/agents/$fname" ]]; then
      echo "  NOT_INSTALLED: core/agents/$fname missing from agents/"
      NOT_INSTALLED=$((NOT_INSTALLED + 1))
    fi
  done
fi

# ---------------------------------------------------------------------------
# Rules parity: core/_index.yaml installed paths vs generated artifacts
# ---------------------------------------------------------------------------
echo ""
echo "--- Rules (index) ---"

CURSOR_RULES="$PLUGIN_ROOT/.cursor/rules"
CLAUDE_RULES="$PLUGIN_ROOT/.claude/rules"
EXPECTED_CURSOR_RULES="$TMPDIR/expected-cursor-rules.txt"
EXPECTED_CLAUDE_RULES="$TMPDIR/expected-claude-rules.txt"
: > "$EXPECTED_CURSOR_RULES"
: > "$EXPECTED_CLAUDE_RULES"

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "  NOT_INSTALLED: core/_index.yaml missing; cannot verify indexed rules"
  NOT_INSTALLED=$((NOT_INSTALLED + 1))
else
  while IFS=$'\t' read -r rule_id source_path cursor_path claude_path; do
    [[ -n "${rule_id:-}" ]] || continue
    source_file="$PLUGIN_ROOT/$source_path"

    if [[ ! -f "$source_file" ]]; then
      echo "  NOT_INSTALLED: $source_path missing (source for rule $rule_id)"
      NOT_INSTALLED=$((NOT_INSTALLED + 1))
    fi

    if [[ -n "${cursor_path:-}" && "$cursor_path" != "null" ]]; then
      echo "$cursor_path" >> "$EXPECTED_CURSOR_RULES"
      cursor_file="$PLUGIN_ROOT/$cursor_path"

      if [[ ! -f "$cursor_file" ]]; then
        echo "  NOT_INSTALLED: $cursor_path missing (installed_cursor for rule $rule_id)"
        NOT_INSTALLED=$((NOT_INSTALLED + 1))
      elif [[ -f "$source_file" ]] && ! diff -qB <(normalize_rule_content "$source_file") <(normalize_rule_content "$cursor_file") > /dev/null 2>&1; then
        echo "  DRIFT: $source_path differs from $cursor_path"
        DRIFT=$((DRIFT + 1))
      fi
    fi

    if [[ -n "${claude_path:-}" && "$claude_path" != "null" ]]; then
      echo "$claude_path" >> "$EXPECTED_CLAUDE_RULES"
      claude_file="$PLUGIN_ROOT/$claude_path"

      if [[ ! -f "$claude_file" ]]; then
        echo "  NOT_INSTALLED: $claude_path missing (installed_claude for rule $rule_id)"
        NOT_INSTALLED=$((NOT_INSTALLED + 1))
      elif [[ -f "$source_file" ]] && ! diff -qB <(normalize_rule_content "$source_file") <(normalize_rule_content "$claude_file") > /dev/null 2>&1; then
        echo "  DRIFT: $source_path differs from $claude_path"
        DRIFT=$((DRIFT + 1))
      fi
    fi
  done < <(index_rules)
fi

if [[ -d "$CURSOR_RULES" ]]; then
  for installed in "$CURSOR_RULES"/*.mdc; do
    [[ -f "$installed" ]] || continue
    rel_path="${installed#$PLUGIN_ROOT/}"

    if ! awk -v rel="$rel_path" '$0 == rel { found=1 } END { exit found ? 0 : 1 }' "$EXPECTED_CURSOR_RULES"; then
      echo "  ORPHAN: $rel_path (not listed as installed_cursor in core/_index.yaml)"
      ORPHANS=$((ORPHANS + 1))
    fi
  done
fi

if [[ -d "$CLAUDE_RULES" ]]; then
  for installed in "$CLAUDE_RULES"/*.md; do
    [[ -f "$installed" ]] || continue
    rel_path="${installed#$PLUGIN_ROOT/}"

    if ! awk -v rel="$rel_path" '$0 == rel { found=1 } END { exit found ? 0 : 1 }' "$EXPECTED_CLAUDE_RULES"; then
      echo "  ORPHAN: $rel_path (not listed as installed_claude in core/_index.yaml)"
      ORPHANS=$((ORPHANS + 1))
    fi
  done
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "METRICS:"
echo "  drift_count=$DRIFT"
echo "  orphan_count=$ORPHANS"
echo "  not_installed_count=$NOT_INSTALLED"
echo "=== DONE ==="

exit 0
