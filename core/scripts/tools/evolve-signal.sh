#!/usr/bin/env bash
set -euo pipefail

# Tier 0 pre-filter for /evolve. Counts NEW signals since INDEX.last_processed_total.
# Portable: count-based delta (no mtime math). Always exits 0.

DIARY_ROOT="${CF_DIARY_ROOT:-$HOME/worklogs/diaries}"
LEARN_ROOT="${CF_LEARN_ROOT:-$HOME/worklogs/learnings}"
LESSONS_ROOT="${CF_LESSONS_ROOT:-.claude/lessons}"
THRESHOLD="${CF_EVOLVE_THRESHOLD:-5}"
INDEX_FILE="${DIARY_ROOT}/INDEX.yaml"

count_yaml() {
  [ -d "$1" ] || { echo 0; return; }
  find "$1" -name "*.yaml" ! -name "INDEX.yaml" 2>/dev/null | wc -l | awk '{print $1}'
}

# A diary whose decisions/worked/failed are all empty is a baseline stub written
# by the SessionEnd hook, not signal. Counting stubs inflates the threshold and
# fires /evolve on files containing nothing.
#
# Enriched means the key actually carries an item: block form (`decisions:` on
# its own line followed by an INDENTED item) or a non-empty inline array. A bare
# `decisions:` with no item does NOT count — core/skills/diary/SKILL.md:38 has
# /diary create exactly that before appending, so an interrupted call leaves a
# stub that must not read as signal. `[ \t]` (not `[[:space:]]`, which includes
# newlines) keeps the block form from matching across a blank line into the next
# key's content.
count_enriched_diaries() {
  [ -d "$1" ] || { echo 0; return; }
  local n=0 f
  while IFS= read -r f; do
    if rg -U -q '^(decisions|worked|failed):[ \t]*\n[ \t]+\S' "$f" 2>/dev/null \
       || rg -q '^(decisions|worked|failed):[ \t]*\[.+\]' "$f" 2>/dev/null; then
      n=$((n+1))
    fi
  done < <(find "$1" -name "*.yaml" ! -name "INDEX.yaml" 2>/dev/null)
  echo "$n"
}

CURRENT=$(( $(count_enriched_diaries "$DIARY_ROOT") + $(count_yaml "$LESSONS_ROOT") + $(count_yaml "$LEARN_ROOT") ))

LAST=0
if [ -f "$INDEX_FILE" ]; then
  LAST=$(rg -oP '^last_processed_total:\s*\K[0-9]+' "$INDEX_FILE" 2>/dev/null || echo 0)
fi
[ -z "$LAST" ] && LAST=0

NEW=$((CURRENT - LAST))
[ "$NEW" -lt 0 ] && NEW=0

if [ "$NEW" -ge "$THRESHOLD" ]; then
  echo "SIGNAL ${NEW} READY"
else
  echo "SIGNAL ${NEW} NO-SIGNAL"
fi
exit 0
