#!/usr/bin/env bash
set -uo pipefail   # never `-e`: a PostToolUse hook must not break the tool flow

# wiki-nudge.sh (PostToolUse — matcher Bash)
# compile-wiki (Karpathy Wiki pattern) went undiscovered for months because nothing
# ever surfaced it — SKILL.md described good trigger conditions but also said
# "Triggered manually", and its docs pointed at a fictional ${CLAUDE_PLUGIN_DATA}
# storage path. Both are fixed in core/skills/compile-wiki/SKILL.md; this hook is
# the deterministic backstop (same pattern as mcp-context-guard.sh): pack-context
# is compile-wiki's own documented Step 2 precursor, so 2+ pack-context calls in one
# session with zero wikis ever compiled is a strong, cheap-to-check signal that the
# skill is being missed. Fires once — after any wiki exists anywhere, it goes quiet
# permanently (the fixed SKILL.md description governs proactive use from then on).

HOOK_JSON="$(cat 2>/dev/null || true)"
[ -z "$HOOK_JSON" ] && exit 0

jqr() { printf '%s' "$HOOK_JSON" | jq -r "$1" 2>/dev/null || printf ''; }

TOOL="$(jqr '.tool_name // ""')"
[ "$TOOL" = "Bash" ] || exit 0

CMD="$(jqr '.tool_input.command // ""')"
case "$CMD" in
  *pack-context.sh*) ;;
  *) exit 0 ;;
esac

# Already compiled at least one wiki, ever — the fixed SKILL.md's own proactive
# trigger conditions take over from here; stop nudging.
WIKI_DIR="$HOME/worklogs/wiki"
if [ -d "$WIKI_DIR" ] && [ -n "$(find "$WIKI_DIR" -maxdepth 2 -name 'index.md' -print -quit 2>/dev/null)" ]; then
  exit 0
fi

SESSION="$(jqr '.session_id // ""')"
[ -z "$SESSION" ] && SESSION="$(printf '%s' "${PWD}-$(date +%Y%m%d)" | md5 -q 2>/dev/null || printf '%s' "${PWD}-$(date +%Y%m%d)" | md5sum 2>/dev/null | cut -d' ' -f1)"
SESSION="$(printf '%s' "$SESSION" | tr -c 'A-Za-z0-9_.-' '_')"

STATE_DIR="${CF_MCP_STATE_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$STATE_DIR" 2>/dev/null || true
STATE="${STATE_DIR%/}/cf-wiki-nudge-${SESSION}.count"

printf 'x\n' >> "$STATE" 2>/dev/null || true
COUNT="$(wc -l < "$STATE" 2>/dev/null | tr -d ' ')"
case "$COUNT" in ''|*[!0-9]*) COUNT=1 ;; esac

# Nudge exactly once per session, on the 2nd pack-context call (not the 1st — a
# single one-off lookup doesn't justify compiling a wiki; a 2nd on an unindexed
# area does, per the skill's own "compile once, query cheap" framing).
if [ "$COUNT" -eq 2 ]; then
  msg="ContextForge (core/skills/compile-wiki): pack-context has been used twice this session and no wiki has ever been compiled (~/worklogs/wiki/ is empty). If this domain will be queried again, consider /compile-wiki --domain <name> --sources <path> now — compile once, query cheap, instead of re-packing raw source each time."
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' \
    "$(printf '%s' "$msg" | jq -Rs .)"
fi
exit 0
