#!/usr/bin/env bash
# benchmark-tokens.sh — Measure token efficiency of all plugin content.
#
# Scans core/rules/*.md, core/skills/*/SKILL.md, core/agents/*.md
# For each file: outputs lines, words, estimated tokens (words * 1.3, rounded)
# Outputs a Markdown table with totals and threshold warnings.
#
# Usage:
#   bash core/scripts/tools/benchmark-tokens.sh [--baseline] [--compare <file>]
#
# Options:
#   --baseline          Save stats to core/benchmarks/baseline-YYYY-MM-DD.tsv
#   --compare <file>    Load TSV and show delta vs current
#
# Token estimate: est_tokens = int(words * 1.3 + 0.5)
# Thresholds: rules >120 lines flagged, skills/agents >100 lines flagged

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

RULES_THRESHOLD=120
SKILLS_THRESHOLD=100

_BASELINE=false
_COMPARE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline) _BASELINE=true; shift ;;
    --compare) _COMPARE="$2"; shift 2 ;;
    --help)
      echo "Usage: benchmark-tokens.sh [--baseline] [--compare <tsv-file>]"
      echo "  --baseline         Save current stats to core/benchmarks/baseline-YYYY-MM-DD.tsv"
      echo "  --compare <file>   Compare current stats against saved TSV baseline"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Token estimate: int(words * 1.3 + 0.5)
est_tokens() {
  awk -v w="$1" 'BEGIN { printf "%d\n", int(w * 1.3 + 0.5) }'
}

# Look up prior token count from compare file using awk (bash 3.2 safe)
lookup_prior() {
  local relpath="$1"
  local cmpfile="$2"
  awk -v key="$relpath" 'NR>1 && $1==key { print $4; found=1; exit } END { if (!found) print "NEW" }' \
    FS='\t' "$cmpfile"
}

if [[ -n "$_COMPARE" && ! -f "$_COMPARE" ]]; then
  echo "ERROR: compare file not found: $_COMPARE" >&2
  exit 1
fi

TODAY=$(date +%Y-%m-%d)
BASELINE_DIR="$PLUGIN_ROOT/core/benchmarks"
BASELINE_FILE="$BASELINE_DIR/baseline-$TODAY.tsv"

# Collect files: rules, skills, agents
TMPLIST=$(mktemp)
trap 'rm -f "$TMPLIST"' EXIT

find "$PLUGIN_ROOT/core/rules"  -name "*.md"     | sort | while IFS= read -r f; do echo "rule	$f"; done >> "$TMPLIST"
find "$PLUGIN_ROOT/core/skills" -name "SKILL.md" | sort | while IFS= read -r f; do echo "skill	$f"; done >> "$TMPLIST"
find "$PLUGIN_ROOT/core/agents" -name "*.md"     | sort | while IFS= read -r f; do echo "agent	$f"; done >> "$TMPLIST"

# Print table header
if [[ -n "$_COMPARE" ]]; then
  printf "| %-52s | %-5s | %5s | %5s | %10s | %7s |\n" "File" "Type" "Lines" "Words" "Est.Tokens" "Delta"
  printf "|%-54s|%-7s|%7s|%7s|%12s|%9s|\n" \
    "$(printf '%0.s-' {1..54})" "$(printf '%0.s-' {1..7})" \
    "$(printf '%0.s-' {1..7})" "$(printf '%0.s-' {1..7})" \
    "$(printf '%0.s-' {1..12})" "$(printf '%0.s-' {1..9})"
else
  printf "| %-52s | %-5s | %5s | %5s | %10s |\n" "File" "Type" "Lines" "Words" "Est.Tokens"
  printf "|%-54s|%-7s|%7s|%7s|%12s|\n" \
    "$(printf '%0.s-' {1..54})" "$(printf '%0.s-' {1..7})" \
    "$(printf '%0.s-' {1..7})" "$(printf '%0.s-' {1..7})" \
    "$(printf '%0.s-' {1..12})"
fi

total_lines=0
total_words=0
total_tokens=0

# TSV accumulator written to temp file for baseline
TSVTMP=$(mktemp)
printf "file\tlines\twords\test_tokens\tdate\n" > "$TSVTMP"

while IFS=$'\t' read -r typ fpath; do
  rel="${fpath#$PLUGIN_ROOT/}"
  lines=$(wc -l < "$fpath" | tr -d ' ')
  words=$(wc -w < "$fpath" | tr -d ' ')
  tokens=$(est_tokens "$words")

  total_lines=$((total_lines + lines))
  total_words=$((total_words + words))
  total_tokens=$((total_tokens + tokens))

  # Threshold flag
  flag=""
  if [[ "$typ" == "rule" && "$lines" -gt "$RULES_THRESHOLD" ]]; then
    flag=" *"
  elif [[ ( "$typ" == "skill" || "$typ" == "agent" ) && "$lines" -gt "$SKILLS_THRESHOLD" ]]; then
    flag=" *"
  fi

  # TSV row
  printf "%s\t%s\t%s\t%s\t%s\n" "$rel" "$lines" "$words" "$tokens" "$TODAY" >> "$TSVTMP"

  if [[ -n "$_COMPARE" ]]; then
    prior=$(lookup_prior "$rel" "$_COMPARE")
    if [[ "$prior" == "NEW" ]]; then
      delta="NEW"
    else
      diff_val=$((tokens - prior))
      if [[ $diff_val -gt 0 ]]; then
        delta="+$diff_val"
      elif [[ $diff_val -lt 0 ]]; then
        delta="$diff_val"
      else
        delta="0"
      fi
    fi
    printf "| %-52s | %-5s | %5d | %5d | %10s | %7s |\n" \
      "$rel" "$typ" "$lines" "$words" "${tokens}${flag}" "$delta"
  else
    printf "| %-52s | %-5s | %5d | %5d | %10s |\n" \
      "$rel" "$typ" "$lines" "$words" "${tokens}${flag}"
  fi
done < "$TMPLIST"

# Totals row
if [[ -n "$_COMPARE" ]]; then
  printf "|%-54s|%-7s|%7s|%7s|%12s|%9s|\n" \
    "$(printf '%0.s-' {1..54})" "$(printf '%0.s-' {1..7})" \
    "$(printf '%0.s-' {1..7})" "$(printf '%0.s-' {1..7})" \
    "$(printf '%0.s-' {1..12})" "$(printf '%0.s-' {1..9})"
  printf "| %-52s | %-5s | %5d | %5d | %10d |         |\n" \
    "**TOTAL**" "" "$total_lines" "$total_words" "$total_tokens"
else
  printf "|%-54s|%-7s|%7s|%7s|%12s|\n" \
    "$(printf '%0.s-' {1..54})" "$(printf '%0.s-' {1..7})" \
    "$(printf '%0.s-' {1..7})" "$(printf '%0.s-' {1..7})" \
    "$(printf '%0.s-' {1..12})"
  printf "| %-52s | %-5s | %5d | %5d | %10d |\n" \
    "**TOTAL**" "" "$total_lines" "$total_words" "$total_tokens"
fi

echo ""
echo "* = exceeds threshold (rules >$RULES_THRESHOLD lines, skills/agents >$SKILLS_THRESHOLD lines)"

# Save baseline
if [[ "$_BASELINE" == "true" ]]; then
  mkdir -p "$BASELINE_DIR"
  cp "$TSVTMP" "$BASELINE_FILE"
  echo ""
  echo "Baseline saved: $BASELINE_FILE"
fi

rm -f "$TSVTMP"
