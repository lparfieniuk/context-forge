#!/usr/bin/env bash
set -euo pipefail

# quality-score.sh — deterministic composite quality score for rules and skills.
#
# Uses the Schliff "full-denominator" model: every defined dimension counts
# toward the denominator, so an unmeasured/failed dimension caps the ceiling and
# the score reports honest coverage (e.g. "4/7") instead of hiding gaps. No LLM,
# no network — same input yields the same score on every machine.
#
# Output: TSV `kind<TAB>file<TAB>score<TAB>passed<TAB>total<TAB>missing`
#         plus a trailing `average<TAB><count><TAB><avg>` line.
#
# Usage: quality-score.sh [--plugin-root <path>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-root) PLUGIN_ROOT="$2"; shift 2 ;;
    --help) echo "Usage: quality-score.sh [--plugin-root <path>]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

RULES_DIR="$PLUGIN_ROOT/core/rules"
SKILLS_DIR="$PLUGIN_ROOT/core/skills"

# Soft language leaking into a constraints block (weakens a hard constraint).
soft_in_constraints() {
  awk '
    /^## SYSTEM CONSTRAINTS/ { s=1; next }
    s && /^## / { s=0 }
    s { print }
  ' "$1" | rg -c '\bshould\b|\bsuggest\b|\bconsider\b|\bmay\b|\bmight\b|\bcould\b|\bprobably\b|\btry\b' 2>/dev/null || true
}

fmt() { awk "BEGIN{printf \"%.2f\", $1/$2}"; }

printf 'kind\tfile\tscore\tpassed\ttotal\tmissing\n'

SCORES=""  # space-separated passed/total fractions, averaged once at the end

score_rule() {
  local f="$1" rel="$2" passed=0 total=7 missing=""
  rg -q '^## SYSTEM CONSTRAINTS' "$f" 2>/dev/null && passed=$((passed+1)) || missing="${missing}constraints,"
  local hard; hard=$(rg -o 'NEVER|ALWAYS|BANNED' "$f" 2>/dev/null | wc -l | tr -d ' ' || true)
  [ "${hard:-0}" -ge 5 ] && passed=$((passed+1)) || missing="${missing}hard-density,"
  local soft; soft=$(soft_in_constraints "$f"); soft="${soft:-0}"
  [ "$soft" -eq 0 ] && passed=$((passed+1)) || missing="${missing}soft-language,"
  rg -q '^## Few-shot' "$f" 2>/dev/null && passed=$((passed+1)) || missing="${missing}few-shot,"
  rg -q '^## Validation gate' "$f" 2>/dev/null && passed=$((passed+1)) || missing="${missing}gate,"
  [ -f "${f%.md}.yaml" ] && passed=$((passed+1)) || missing="${missing}yaml,"
  local bytes; bytes=$(wc -c < "$f" | tr -d ' ')
  [ "$bytes" -le 8000 ] && passed=$((passed+1)) || missing="${missing}budget,"
  printf 'rule\t%s\t%s\t%d\t%d\t%s\n' "$rel" "$(fmt "$passed" "$total")" "$passed" "$total" "${missing%,}"
  SCORES="$SCORES $passed/$total"
}

score_skill() {
  local f="$1" rel="$2" passed=0 total=6 missing=""
  rg -q '^name:' "$f" 2>/dev/null && passed=$((passed+1)) || missing="${missing}name,"
  rg -q '^description:' "$f" 2>/dev/null && passed=$((passed+1)) || missing="${missing}description,"
  rg -q '^## What This Does|^## Purpose' "$f" 2>/dev/null && passed=$((passed+1)) || missing="${missing}purpose,"
  rg -q '^## Constraints' "$f" 2>/dev/null && passed=$((passed+1)) || missing="${missing}constraints,"
  rg -q '<example>|^## Few-shot' "$f" 2>/dev/null && passed=$((passed+1)) || missing="${missing}example,"
  local bytes; bytes=$(wc -c < "$f" | tr -d ' ')
  [ "$bytes" -le 12000 ] && passed=$((passed+1)) || missing="${missing}budget,"
  printf 'skill\t%s\t%s\t%d\t%d\t%s\n' "$rel" "$(fmt "$passed" "$total")" "$passed" "$total" "${missing%,}"
  SCORES="$SCORES $passed/$total"
}

if [ -d "$RULES_DIR" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    score_rule "$f" "${f#"$PLUGIN_ROOT"/}"
  done < <(find "$RULES_DIR" -name '*.md' | sort)
fi

if [ -d "$SKILLS_DIR" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    score_skill "$f" "${f#"$PLUGIN_ROOT"/}"
  done < <(find "$SKILLS_DIR" -name 'SKILL.md' | sort)
fi

echo "$SCORES" | awk '{
  s=0; n=0;
  for (i=1; i<=NF; i++) { split($i, a, "/"); if (a[2] > 0) { s += a[1]/a[2]; n++ } }
  if (n > 0) printf "average\t%d\t%.2f\n", n, s/n
}'
