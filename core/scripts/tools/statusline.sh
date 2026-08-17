#!/usr/bin/env bash
# statusline.sh — one-line Claude Code status line (rule 010 + rule 006).
#
# Wire it up in settings.json:
#   "statusLine": { "type": "command",
#     "command": "bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/statusline.sh" }
#
# Claude Code pipes a JSON payload on stdin (model, workspace, transcript_path,
# cost). This renders: model, cwd+branch, context-budget %, cache warmth, cost.
# It must NEVER crash — a failing status line would break the prompt — so every
# lookup degrades to a sane default.

set -uo pipefail   # no `-e`: a status line must always print something

case "${1:-}" in
  --help|-h)
    cat <<'USAGE'
Usage: statusline.sh

One-line Claude Code status line (rule 010 + rule 006). Reads session JSON on
stdin. Wire it into settings.json under "statusLine"; takes no arguments.
USAGE
    exit 0
    ;;
esac

INPUT="$(cat 2>/dev/null || true)"

jqr() { echo "$INPUT" | jq -r "$1" 2>/dev/null || echo ""; }

MODEL="$(jqr '.model.display_name // .model.id // "?"')"; [ -z "$MODEL" ] && MODEL="?"
CWD="$(jqr '.workspace.current_dir // .cwd // ""')"
TRANSCRIPT="$(jqr '.transcript_path // ""')"
COST="$(jqr '.cost.total_cost_usd // 0')"

DIR_NAME="?"; [ -n "$CWD" ] && DIR_NAME="$(basename "$CWD")"

# Git branch (best effort, scoped to the reported cwd).
BRANCH=""
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  BRANCH="$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi

# Context budget — reuse the rule-010 run-log proxy (turns * ~500 tokens).
effective_k=130
case "$MODEL" in
  *[Oo]pus*|*[Ss]onnet*|*[Ff]able*) effective_k=650 ;;
esac
pct=0
if [ -n "$CWD" ]; then
  hash_val="$(printf '%s' "$CWD" | md5 -q 2>/dev/null || printf '%s' "$CWD" | md5sum 2>/dev/null | cut -d' ' -f1)"
  hash_val="${hash_val:0:8}"
  log_file="$HOME/worklogs/runs/$(date +%Y-%m-%d)-${hash_val}.yaml"
  if [ -f "$log_file" ]; then
    turns="$(rg -c '^- ts:' "$log_file" 2>/dev/null || echo 0)"
    pct=$(( turns * 500 / 1000 * 100 / effective_k ))
  fi
fi
[ "$pct" -gt 100 ] && pct=100
if   [ "$pct" -lt 60 ]; then STATUS="OK"
elif [ "$pct" -lt 70 ]; then STATUS="WARN"
elif [ "$pct" -lt 80 ]; then STATUS="PRESSURE"
else STATUS="CRITICAL"; fi

# Cache warmth — the default prompt cache TTL is 5 min (rule 006). Time since
# the transcript last changed approximates time since the last turn.
CACHE="cache n/a"
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  now="$(date +%s)"
  # GNU stat must be tried FIRST: `stat -f %m FILE` on GNU means "filesystem
  # status", takes %m as an operand, prints filesystem info to stdout AND exits
  # non-zero — so a BSD-first chain concatenates that garbage with the fallback.
  # BSD stat has no -c, so it fails silently and cleanly the other way round.
  mtime="$(stat -c %Y "$TRANSCRIPT" 2>/dev/null || stat -f %m "$TRANSCRIPT" 2>/dev/null || true)"
  case "$mtime" in ''|*[!0-9]*) mtime="$now" ;; esac
  age_min=$(( (now - mtime) / 60 ))
  [ "$age_min" -lt 0 ] && age_min=0   # guard clock skew / future mtime
  if [ "$age_min" -ge 5 ]; then
    CACHE="cache cold (${age_min}m)"
  else
    CACHE="cache warm (${age_min}m)"
  fi
fi

COST_FMT="$(awk "BEGIN{printf \"%.2f\", ${COST:-0}}" 2>/dev/null || echo "0.00")"

LOC="$DIR_NAME"; [ -n "$BRANCH" ] && LOC="$DIR_NAME ($BRANCH)"

# ASCII-only output: a status line renders under whatever locale the terminal
# has, so multibyte separators are avoided deliberately.
printf 'CF | %s | %s | ctx ~%d%% %s | %s | $%s\n' \
  "$MODEL" "$LOC" "$pct" "$STATUS" "$CACHE" "$COST_FMT"
