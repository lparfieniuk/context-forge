#!/usr/bin/env bash
set -euo pipefail

# Applies an approved /evolve proposal patch, converts + audits, and either
# promotes the proposal to applied/ or reverts. HUMAN-INVOKED ONLY.

ID="${1:-}"
SKIP_AUDIT=0
[ "${2:-}" = "--skip-audit" ] && SKIP_AUDIT=1
if [ -z "$ID" ]; then
  echo "[EVOLVE-APPLY] usage: evolve-apply.sh <id> [--skip-audit]" >&2
  exit 2
fi

EVOLVE_ROOT="${CF_EVOLVE_ROOT:-.claude/evolve}"
PENDING="${EVOLVE_ROOT}/pending/${ID}.yaml"
APPLIED_DIR="${EVOLVE_ROOT}/applied"
LEDGER="${EVOLVE_ROOT}/ledger.tsv"
if [ ! -f "$PENDING" ]; then
  echo "[EVOLVE-APPLY] no pending proposal: ${PENDING}" >&2
  exit 2
fi

# Extract proposal metadata up-front (before any move/revert). Missing -> "-".
# `-m 1` (not `head`) avoids a SIGPIPE under pipefail; strip quotes and any
# stray tab so a field can never corrupt the TSV row.
meta() { rg -m 1 -oP "^${1}:\\s*\\K.+" "$PENDING" 2>/dev/null | tr -d '"\t' || true; }
VERDICT="$(meta verdict)"; VERDICT="${VERDICT:--}"
TARGET="$(meta target)";   TARGET="${TARGET:--}"
CONF="$(meta confidence)"; CONF="${CONF:--}"

# Autoresearch-style outcome ledger: one greppable row per apply attempt
# (status: applied | reverted | reverted-patch ~ keep | discard | crash).
append_ledger() {
  local status="$1"
  mkdir -p "$EVOLVE_ROOT"
  [ -f "$LEDGER" ] || printf 'ts\tid\tverdict\ttarget\tstatus\tconfidence\n' > "$LEDGER"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ID" "$VERDICT" "$TARGET" "$status" "$CONF" >> "$LEDGER"
}

# Extract the patch_text block (YAML literal block, 2-space indented).
PATCH_FILE="$(mktemp)"
awk '
  /^patch_text:[[:space:]]*\|/ { grab=1; next }
  grab {
    if ($0 ~ /^[^[:space:]]/) { grab=0; next }   # next top-level key ends block
    sub(/^  /, "")                                 # strip 2-space indent
    print
  }
' "$PENDING" > "$PATCH_FILE"

revert() {
  git apply -R --whitespace=nowarn "$PATCH_FILE" 2>/dev/null || git checkout -- . 2>/dev/null || true
  rm -f "$PATCH_FILE"
  append_ledger reverted
  echo "[EVOLVE-APPLY] ${ID} reverted"
}

if ! git apply --whitespace=nowarn "$PATCH_FILE" 2>/dev/null; then
  rm -f "$PATCH_FILE"
  append_ledger reverted-patch
  echo "[EVOLVE-APPLY] ${ID} reverted (patch did not apply)"
  exit 1
fi

# Propagate + gate (skippable in tests).
if [ "$SKIP_AUDIT" -eq 0 ]; then
  if ! npm run convert >/dev/null 2>&1 || ! npm run test:audit >/dev/null 2>&1; then
    revert
    exit 1
  fi
fi

# Log the outcome before the bookkeeping move, mirroring the revert path.
append_ledger applied
mkdir -p "$APPLIED_DIR"
mv "$PENDING" "${APPLIED_DIR}/${ID}.yaml"
rm -f "$PATCH_FILE"
echo "[EVOLVE-APPLY] ${ID} applied"
exit 0
