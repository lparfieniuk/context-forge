#!/usr/bin/env bash
set -euo pipefail

# Hook 9: diary-capture.sh (SessionEnd)
# Deterministic baseline diary entry for the self-evolving loop v2.
# Writes one entry per session and maintains INDEX.yaml. Idempotent.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# Consume (and ignore) any hook JSON on stdin so SessionEnd never blocks.
cat >/dev/null 2>&1 || true

DIARY_ROOT="${CF_DIARY_ROOT:-$HOME/worklogs/diaries}"
RUNS_ROOT="${CF_RUNS_ROOT:-$HOME/worklogs/runs}"
LESSONS_ROOT="${CF_LESSONS_ROOT:-.claude/lessons}"

PWD_HASH=$(repo_root_hash)
SESSION_ID="$(date +%Y-%m-%d)-${PWD_HASH}"
DIARY_DIR="${DIARY_ROOT}/$(date +%Y/%m)"
DIARY_FILE="${DIARY_DIR}/$(date +%Y-%m-%d)-${PWD_HASH}.yaml"
INDEX_FILE="${DIARY_ROOT}/INDEX.yaml"

mkdir -p "$DIARY_DIR"

# Baseline already written today: refresh the counters instead of bailing out.
# The diary is day-scoped (SESSION_ID = date + PWD hash), so every later session
# that day must fold its run-log counts in — an exit 0 here froze `signals` at
# whatever the day's first session end saw.
REFRESH=0
if [ -f "$DIARY_FILE" ] && rg -q "^session: ${SESSION_ID}$" "$DIARY_FILE" 2>/dev/null; then
  REFRESH=1
fi

# Derive counts from the run log written by run-log-writer.sh.
RUN_LOG="${RUNS_ROOT}/${SESSION_ID}.yaml"
CMD_COUNT=0
FAIL_COUNT=0
if [ -f "$RUN_LOG" ]; then
  CMD_COUNT=$(rg -c "^- ts:" "$RUN_LOG" 2>/dev/null || echo 0)
  FAIL_COUNT=$(rg -c "status: failure" "$RUN_LOG" 2>/dev/null || echo 0)
fi

# Link failure ledgers created today (sharded YYYY/MM/DD).
LEDGER_DIR="${LESSONS_ROOT}/$(date +%Y/%m/%d)"
LEDGER_REFS=""
if [ -d "$LEDGER_DIR" ]; then
  while IFS= read -r f; do
    LEDGER_REFS="${LEDGER_REFS}  - $(basename "$f" .yaml)\n"
  done < <(find "$LEDGER_DIR" -name "*.yaml" 2>/dev/null)
fi

TS="$(date -u "+%Y-%m-%d %H:%M")"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "none")
case "$BRANCH" in
  fix/*|hotfix/*|bugfix/*) TASK_TYPE="bugfix" ;;
  feature/*|feat/*)        TASK_TYPE="new_feature" ;;
  refactor/*|cleanup/*)    TASK_TYPE="refactor" ;;
  spike/*|poc/*|research/*) TASK_TYPE="spike" ;;
  *)                       TASK_TYPE="unknown" ;;
esac

# Refresh path — hook-owned keys, and what happens to each:
#   session:   never (it IS the day+dir identity)
#   ts:        refreshed — the latest session end
#   task_type: refreshed — must agree with ts, see below
#   branch:    refreshed — must agree with ts, see below
#   failed:    NOT refreshed — see ponytail note
#   signals:   refreshed — the day's run-log counts so far
# `decisions:` and `worked:` belong to /diary and are never touched here.
# ts/task_type/branch move together on purpose: a file claiming the latest session's
# timestamp next to the first session's branch describes a session that never existed.
# ponytail: `failed:` is left alone on refresh — swapping an existing multi-line
# block needs a real YAML parser, and /evolve reads the ledgers straight from
# <IDE_DIR>/lessons/ anyway, so the diary backlink is convenience, not the signal.
if [ "$REFRESH" = 1 ]; then
  TMP="${DIARY_FILE}.tmp"
  sed -e "s|^ts: .*|ts: \"${TS}\"|" \
      -e "s|^task_type: .*|task_type: ${TASK_TYPE}|" \
      -e "s|^branch: .*|branch: ${BRANCH}|" \
      -e "s|^signals: .*|signals: [baseline, \"cmds:${CMD_COUNT}\", \"fails:${FAIL_COUNT}\"]|" \
      "$DIARY_FILE" > "$TMP" && [ -s "$TMP" ] && mv "$TMP" "$DIARY_FILE" || rm -f "$TMP"
  exit 0
fi

# Append baseline keys (works whether the file is new or /diary-created).
{
  echo "session: ${SESSION_ID}"
  echo "ts: \"${TS}\""
  echo "task_type: ${TASK_TYPE}"
  echo "branch: ${BRANCH}"
  if [ ! -f "$DIARY_FILE" ] || ! rg -q "^decisions:" "$DIARY_FILE" 2>/dev/null; then
    echo "decisions: []"
  fi
  if [ ! -f "$DIARY_FILE" ] || ! rg -q "^worked:" "$DIARY_FILE" 2>/dev/null; then
    echo "worked: []"
  fi
  if [ -n "$LEDGER_REFS" ]; then
    echo "failed:"
    printf "%b" "$LEDGER_REFS"
  else
    echo "failed: []"
  fi
  echo "signals: [baseline, \"cmds:${CMD_COUNT}\", \"fails:${FAIL_COUNT}\"]"
} >> "$DIARY_FILE"

# Maintain INDEX.yaml: total_entries + last_entry_ts; preserve last_processed_total.
TOTAL=$(find "$DIARY_ROOT" -name "*.yaml" ! -name "INDEX.yaml" 2>/dev/null | wc -l | awk '{print $1}')
LAST_PROCESSED_TOTAL=0
if [ -f "$INDEX_FILE" ]; then
  LAST_PROCESSED_TOTAL=$(rg -oP '^last_processed_total:\s*\K[0-9]+' "$INDEX_FILE" 2>/dev/null || echo 0)
fi
[ -z "$LAST_PROCESSED_TOTAL" ] && LAST_PROCESSED_TOTAL=0
{
  echo "total_entries: ${TOTAL}"
  echo "last_entry_ts: \"${TS}\""
  echo "last_processed_total: ${LAST_PROCESSED_TOTAL}"
} > "${INDEX_FILE}.tmp" && mv "${INDEX_FILE}.tmp" "$INDEX_FILE"

exit 0
