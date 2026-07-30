#!/usr/bin/env bash
# tools/validate-manifest.sh — Check manifest freshness and integrity
# Exit codes: 0=FRESH, 1=STALE, 2=BROKEN (or missing)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/rg-helpers.sh" 2>/dev/null || true

# Defaults
_TARGET=""
_REPO=""
_IDE_DIR=""
_STALE_DAYS=7

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: validate-manifest.sh --target <repo-path> [--repo <name>] [--ide-dir <dir>]

Check manifest freshness and integrity.

Exit codes:
  0 — FRESH (use as-is)
  1 — STALE (use but refresh recommended)
  2 — BROKEN (must refresh before using)

Options:
  --target <path>   — Path to target repository root (required)
  --repo <name>     — Repository name (default: basename of target)
  --ide-dir <dir>   — IDE directory (.claude or .cursor, auto-detected)

Examples:
  validate-manifest.sh --target /path/to/repo
  validate-manifest.sh --target /path/to/repo --repo my-app --ide-dir .claude
EOF
      exit 0
      ;;
    --target) _TARGET="$2"; shift 2 ;;
    --repo) _REPO="$2"; shift 2 ;;
    --ide-dir) _IDE_DIR="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$_TARGET" ]]; then
  echo "ERROR: --target is required" >&2
  exit 2
fi

_TARGET="$(cd "$_TARGET" 2>/dev/null && pwd)" || { echo "ERROR: target not found: $_TARGET" >&2; exit 2; }

# Auto-detect repo name
if [[ -z "$_REPO" ]]; then
  _REPO="$(basename "$_TARGET")"
fi

# Auto-detect IDE directory
if [[ -z "$_IDE_DIR" ]]; then
  if [[ -d "$_TARGET/.claude" ]]; then
    _IDE_DIR=".claude"
  elif [[ -d "$_TARGET/.cursor" ]]; then
    _IDE_DIR=".cursor"
  else
    _IDE_DIR=".claude"
  fi
fi

MANIFEST="$_TARGET/$_IDE_DIR/shadow/$_REPO/_manifest.lightweight.yaml"

# Check existence
if [[ ! -f "$MANIFEST" ]]; then
  echo "VERDICT: BROKEN"
  echo "REASON: Manifest not found at $MANIFEST"
  exit 2
fi

# --- Age check ---
GENERATED=""
if command -v rg &>/dev/null; then
  GENERATED=$(rg "^  generated:" "$MANIFEST" | head -1 | sed 's/.*generated:[[:space:]]*//' | tr -d '"' | tr -d "'" || echo "")
else
  GENERATED=$(grep "generated:" "$MANIFEST" | head -1 | sed 's/.*generated:[[:space:]]*//' | tr -d '"' | tr -d "'" || echo "")
fi

AGE_DAYS=0
if [[ -n "$GENERATED" ]]; then
  # Parse ISO timestamp to epoch (macOS compatible)
  if date --version &>/dev/null 2>&1; then
    # GNU date
    GEN_EPOCH=$(date -d "$GENERATED" +%s 2>/dev/null || echo "0")
  else
    # BSD date (macOS)
    # Try ISO format
    GEN_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${GENERATED%%.*}" +%s 2>/dev/null || echo "0")
  fi
  NOW_EPOCH=$(date +%s)
  if [[ "$GEN_EPOCH" -gt 0 ]]; then
    AGE_DAYS=$(( (NOW_EPOCH - GEN_EPOCH) / 86400 ))
  fi
fi

# Read stale threshold from manifest
STALE_THRESHOLD=$_STALE_DAYS
THRESHOLD_LINE=$(rg "stale_threshold_days:" "$MANIFEST" 2>/dev/null | head -1 || echo "")
if [[ -n "$THRESHOLD_LINE" ]]; then
  PARSED_THRESHOLD=$(echo "$THRESHOLD_LINE" | sed 's/.*stale_threshold_days:[[:space:]]*//' | tr -d ' ')
  if [[ "$PARSED_THRESHOLD" =~ ^[0-9]+$ ]]; then
    STALE_THRESHOLD="$PARSED_THRESHOLD"
  fi
fi

# --- Orphan check (sample 10 random symbols) ---
ORPHAN_COUNT=0
TOTAL_CHECKED=0

# Extract file paths from symbols section
SYMBOL_FILES=$(rg "^  *file:" "$MANIFEST" 2>/dev/null | sed 's/.*file:[[:space:]]*//' | tr -d '"' | tr -d "'" || echo "")
if [[ -n "$SYMBOL_FILES" ]]; then
  # Sample up to 10 random entries
  SAMPLED=$(echo "$SYMBOL_FILES" | sort -R 2>/dev/null | head -10 || echo "$SYMBOL_FILES" | head -10)
  while IFS= read -r rel_path; do
    [[ -z "$rel_path" ]] && continue
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    if [[ ! -f "$_TARGET/$rel_path" ]]; then
      ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
    fi
  done <<< "$SAMPLED"
fi

# --- Verdict ---
echo "MANIFEST: $MANIFEST"
echo "AGE: ${AGE_DAYS}d (threshold: ${STALE_THRESHOLD}d)"
echo "ORPHANS: ${ORPHAN_COUNT}/${TOTAL_CHECKED} sampled"

if [[ "$ORPHAN_COUNT" -gt 3 ]]; then
  echo "VERDICT: BROKEN"
  echo "REASON: >3 orphaned symbols in sample of $TOTAL_CHECKED"
  exit 2
elif [[ "$AGE_DAYS" -gt "$STALE_THRESHOLD" ]]; then
  echo "VERDICT: STALE"
  echo "REASON: Manifest is ${AGE_DAYS}d old (threshold: ${STALE_THRESHOLD}d)"
  exit 1
elif [[ "$ORPHAN_COUNT" -gt 0 ]]; then
  echo "VERDICT: STALE"
  echo "REASON: ${ORPHAN_COUNT} orphaned symbols found"
  exit 1
else
  echo "VERDICT: FRESH"
  exit 0
fi
