#!/usr/bin/env bash
# Integration test: runs audit-rules and benchmark-tokens; fails on violations.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PLUGIN_ROOT"

echo "=== audit-rules ==="
OUTPUT=$(bash core/scripts/tools/audit-rules.sh 2>&1)
echo "$OUTPUT"

# Fail if any rule has soft violations or missing sections (case-insensitive)
# rg exits 1 on no-match, so use || true to avoid pipefail triggering on clean runs
if echo "$OUTPUT" | rg -qi "fail" 2>/dev/null; then
  echo "[FAIL] audit-rules found violations"
  exit 1
fi

# Fail if rules missing few-shot or validation gate (non-zero count in summary)
MISSING=$(echo "$OUTPUT" | rg "Rules missing" 2>/dev/null | rg -c " [1-9]" 2>/dev/null || echo "0")
if [ "${MISSING:-0}" -gt 0 ]; then
  echo "[FAIL] $MISSING rules missing required sections"
  exit 1
fi

echo "=== benchmark-tokens ==="
OUTPUT=$(bash core/scripts/tools/benchmark-tokens.sh 2>&1)
echo "$OUTPUT"

# Fail if any file exceeds threshold (marked with ' *' appended to token count)
if echo "$OUTPUT" | rg -q " \* \|"; then
  echo "[FAIL] benchmark-tokens found files exceeding size thresholds"
  exit 1
fi

echo "=== validate-index ==="
VALIDATE_OUT=$(npm run validate-index 2>&1 | tail -5)
echo "$VALIDATE_OUT"
if ! echo "$VALIDATE_OUT" | rg -q "STATUS: OK"; then
  echo "[FAIL] validate-index failed"
  exit 1
fi

echo "[PASS] All checks passed"
