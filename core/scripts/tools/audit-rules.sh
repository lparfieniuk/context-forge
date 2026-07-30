#!/usr/bin/env bash
# audit-rules.sh — Audit rule quality across core/rules/*.md
#
# Checks per rule file:
#   1. Hard constraint density (NEVER|ALWAYS|BANNED count)
#   2. Soft language violations in ## SYSTEM CONSTRAINTS section only
#   3. Few-shot section present (## Few-shot)
#   4. Validation gate present (## Validation gate)
#   5. Corresponding .yaml exists
#
# Output: Markdown table + summary
#
# Usage:
#   bash core/scripts/tools/audit-rules.sh [--plugin-root <path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-root) PLUGIN_ROOT="$2"; shift 2 ;;
    --help)
      echo "Usage: audit-rules.sh [--plugin-root <path>]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

RULES_DIR="$PLUGIN_ROOT/core/rules"

if [[ ! -d "$RULES_DIR" ]]; then
  echo "ERROR: rules directory not found: $RULES_DIR" >&2
  exit 1
fi

total_rules=0
clean_rules=0
missing_fewshot=0
missing_gate=0

echo "| Rule | Hard Constraints | Soft Violations | Few-shot | Val.Gate | YAML |"
echo "|------|----------------:|----------------:|:--------:|:--------:|:----:|"

while IFS= read -r f; do
  [[ ! -f "$f" ]] && continue
  total_rules=$((total_rules + 1))
  name=$(basename "$f")

  # 1. Hard constraint density
  hard=$(rg -c 'NEVER|ALWAYS|BANNED' "$f" 2>/dev/null || echo 0)

  # 2. Soft language violations — SYSTEM CONSTRAINTS section only
  # Extract lines between "## SYSTEM CONSTRAINTS" and next "##" heading
  soft=$(awk '
    /^## SYSTEM CONSTRAINTS/ { in_section=1; next }
    in_section && /^## / { in_section=0 }
    in_section { print }
  ' "$f" | rg -c '\bshould\b|\bsuggest\b|\bconsider\b|\bmay\b|\bmight\b|\bcould\b' 2>/dev/null || echo 0)

  # 3. Few-shot section
  if rg -q '## Few-shot' "$f" 2>/dev/null; then
    fewshot="pass"
  else
    fewshot="FAIL"
    missing_fewshot=$((missing_fewshot + 1))
  fi

  # 4. Validation gate
  if rg -q '## Validation gate' "$f" 2>/dev/null; then
    gate="pass"
  else
    gate="FAIL"
    missing_gate=$((missing_gate + 1))
  fi

  # 5. Corresponding .yaml
  yaml_file="${f%.md}.yaml"
  if [[ -f "$yaml_file" ]]; then
    yaml_check="pass"
  else
    yaml_check="FAIL"
  fi

  # Track clean rules (0 soft violations)
  if [[ "$soft" -eq 0 ]]; then
    clean_rules=$((clean_rules + 1))
  fi

  # Shorten name for display
  display="${name%.md}"
  printf "| %-35s | %16s | %15s | %8s | %8s | %4s |\n" \
    "$display" "$hard" "$soft" "$fewshot" "$gate" "$yaml_check"

done < <(find "$RULES_DIR" -name "*.md" | sort)

echo ""
echo "## Summary"
echo ""
echo "| Metric | Count |"
echo "|--------|------:|"
echo "| Total rules | $total_rules |"
echo "| Rules with 0 soft violations | $clean_rules |"
echo "| Rules missing few-shot section | $missing_fewshot |"
echo "| Rules missing validation gate | $missing_gate |"
