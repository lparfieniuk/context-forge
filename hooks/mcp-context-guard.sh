#!/usr/bin/env bash
set -uo pipefail   # never `-e`: a PostToolUse hook must not break the tool flow

# mcp-context-guard.sh (PostToolUse — matcher mcp__.*)
# Rule 015-cf-mcp-tools: MCP tool results linger in context for the rest of the
# session and were the single biggest usage driver observed (~64%). This hook
# tracks cumulative MCP output per session and, when it crosses a threshold,
# injects `additionalContext` telling the agent to run /compact now — a
# deterministic auto-nudge (a hook cannot invoke /compact itself, but the agent
# acts on the injected context). Silent below threshold; fires once per crossing.

HOOK_JSON="$(cat 2>/dev/null || true)"
[ -z "$HOOK_JSON" ] && exit 0

jqr() { printf '%s' "$HOOK_JSON" | jq -r "$1" 2>/dev/null || printf ''; }

TOOL="$(jqr '.tool_name // ""')"
case "$TOOL" in
  mcp__*) ;;
  *) exit 0 ;;   # scope to MCP tools even if the matcher is broadened
esac

SESSION="$(jqr '.session_id // ""')"
[ -z "$SESSION" ] && SESSION="$(printf '%s' "${PWD}-$(date +%Y%m%d)" | md5 -q 2>/dev/null || printf '%s' "${PWD}-$(date +%Y%m%d)" | md5sum 2>/dev/null | cut -d' ' -f1)"
SESSION="$(printf '%s' "$SESSION" | tr -c 'A-Za-z0-9_.-' '_')"

THRESH_KB="${CF_MCP_COMPACT_KB:-50}"
case "$THRESH_KB" in ''|*[!0-9]*) THRESH_KB=50 ;; esac
STATE_DIR="${CF_MCP_STATE_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$STATE_DIR" 2>/dev/null || true
# Append-only log (one call's byte count per line). A per-session file that the
# OS clears with TMPDIR; not GC'd here. Appending avoids the lost-update race of
# a read-modify-write counter when Claude Code dispatches parallel MCP calls
# (small POSIX appends are atomic), so the running total stays correct.
STATE="${STATE_DIR%/}/cf-mcp-${SESSION}.log"

# Serialized size of this MCP result (captures object payloads, not just strings).
RESULT_BYTES="$(printf '%s' "$HOOK_JSON" | jq -c '.tool_response // .tool_result // ""' 2>/dev/null | wc -c | tr -d ' ')"
case "$RESULT_BYTES" in ''|*[!0-9]*) RESULT_BYTES=0 ;; esac

printf '%s\n' "$RESULT_BYTES" >> "$STATE" 2>/dev/null || true
NEW="$(awk '{s+=$1} END{print s+0}' "$STATE" 2>/dev/null || printf '%s' "$RESULT_BYTES")"
case "$NEW" in ''|*[!0-9]*) NEW=$RESULT_BYTES ;; esac
PREV=$((NEW - RESULT_BYTES))
[ "$PREV" -lt 0 ] && PREV=0

THRESH_BYTES=$((THRESH_KB * 1024))
[ "$THRESH_BYTES" -le 0 ] && exit 0

# Nudge only on the call that pushes the running total past a threshold multiple.
if [ $((NEW / THRESH_BYTES)) -gt $((PREV / THRESH_BYTES)) ]; then
  kb=$((NEW / 1024))
  msg="ContextForge (rule 015-cf-mcp-tools): MCP tool results have accumulated to ~${kb}KB this session. Run /compact now to flush stale MCP results before continuing — unless you still need them in context."
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' \
    "$(printf '%s' "$msg" | jq -Rs .)"
fi
exit 0
