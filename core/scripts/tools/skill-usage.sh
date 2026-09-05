#!/usr/bin/env bash
set -euo pipefail

# skill-usage.sh — count real ContextForge skill invocations in Claude Code transcripts.
#
# Three call shapes are counted separately, because they answer different questions:
#   skill_tool  — the model invoked the skill itself   ("skill":"context-forge:<id>")
#   slash       — the user typed it                    (<command-name>/context-forge:<id>)
#   agent       — a sub-agent was spawned              ("subagent_type":"context-forge:<id>")
#
# RETENTION CEILING: Claude Code deletes transcripts after `cleanupPeriodDays`
# (default 30, verified in the 2.1.261 binary). This scan therefore reports a
# rolling ~30-day window, never full project history. For history past that
# window an append-only hook log is the only source.
#
# Output: TSV `skill<TAB>skill_tool<TAB>slash<TAB>agent<TAB>total<TAB>last_used`
# Usage: skill-usage.sh [--plugin-root <path>] [--projects <dir>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PROJECTS="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-root) PLUGIN_ROOT="$2"; shift 2 ;;
    --projects) PROJECTS="$2"; shift 2 ;;
    --help) echo "Usage: skill-usage.sh [--plugin-root <path>] [--projects <dir>]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

INDEX="$PLUGIN_ROOT/core/_index.yaml"
[[ -f "$INDEX" ]] || { echo "Missing index: $INDEX" >&2; exit 1; }
[[ -d "$PROJECTS" ]] || { echo "Missing transcripts dir: $PROJECTS" >&2; exit 1; }

# Every id whose entry declares `type: skill` or `type: agent`.
ids="$(awk '/^[[:space:]]*- id:/ {id=$3} /^[[:space:]]*type:[[:space:]]*(skill|agent)/ && id {print id; id=""}' "$INDEX")"

matches="$(rg -o --with-filename --no-line-number \
  -e '"skill":"(context-forge:)?[a-z0-9-]+"' \
  -e '<command-name>/(context-forge:)?[a-z0-9-]+</command-name>' \
  -e '"subagent_type":"(context-forge:)?[a-z0-9-]+"' \
  "$PROJECTS" -g '*.jsonl' 2>/dev/null || true)"

printf 'skill\tskill_tool\tslash\tagent\ttotal\tlast_used\n'

printf '%s\n' "$ids" | while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  hits="$(printf '%s\n' "$matches" | rg -F "$id" || true)"
  st=0; sl=0; ag=0; last='-'
  if [[ -n "$hits" ]]; then
    st=$(printf '%s\n' "$hits" | rg -c "\"skill\":\"(context-forge:)?${id}\"" || true)
    sl=$(printf '%s\n' "$hits" | rg -c "<command-name>/(context-forge:)?${id}</command-name>" || true)
    ag=$(printf '%s\n' "$hits" | rg -c "\"subagent_type\":\"(context-forge:)?${id}\"" || true)
    # newest transcript that mentions this id, as YYYY-MM-DD
    newest=$(printf '%s\n' "$hits" | sed 's/\.jsonl:.*/.jsonl/' | sort -u \
      | while IFS= read -r f; do
          [[ -f "$f" ]] || continue
          # BSD stat first, GNU second: `stat -f` on GNU prints to stdout AND exits non-zero,
          # so the chain must not be trusted on exit code alone (rule 004).
          stat -f '%m %N' "$f" 2>/dev/null || stat -c '%Y %n' "$f" 2>/dev/null || true
        done | sort -rn | head -1 | cut -d' ' -f1)
    [[ -n "${newest:-}" ]] && last=$(date -r "$newest" '+%Y-%m-%d')
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "${st:-0}" "${sl:-0}" "${ag:-0}" "$(( ${st:-0} + ${sl:-0} + ${ag:-0} ))" "$last"
done | sort -t"$(printf '\t')" -k5,5nr
