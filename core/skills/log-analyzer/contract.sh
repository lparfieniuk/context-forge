#!/usr/bin/env bash
# contract.sh — machine-checkable output contract for the log-analyzer skill.
#
# Usage: contract.sh <sample-file>   (or sample on stdin)
# Exit 0 = output conforms to the [RCA] envelope; exit 1 = violation.
#
# Contract (from core/skills/log-analyzer/SKILL.md Output Format):
#   [RCA] opens, [END RCA] closes (multiple blocks allowed, blank-line separated)
#   - Root cause: <text>      required in every block
#   - Failing file: <path>    required in every block
#   - Fix: <text>             required in every block

set -euo pipefail

INPUT="${1:-/dev/stdin}"
[[ -f "$INPUT" ]] || { echo "contract: no such file: $INPUT" >&2; exit 1; }

fail() { echo "log-analyzer contract violation: $1" >&2; exit 1; }

BLOCKS="$(awk '/^\[RCA\]/{n++} END{print n+0}' "$INPUT")"
[[ "$BLOCKS" -ge 1 ]] || fail "no [RCA] block found"

awk '
  /^\[RCA\]/        { block++; seen_root[block]=0; seen_file[block]=0; seen_fix[block]=0; next }
  /^\[END RCA\]/    { next }
  /^- Root cause: ./ { seen_root[NR_block]=1 }
  /^- Failing file: / { seen_file[NR_block]=1 }
  /^- Fix: ./        { seen_fix[NR_block]=1 }
' "$INPUT" > /dev/null

# Per-block field check done in awk above needs block tracking; simpler re-scan:
awk -v total="$BLOCKS" '
  function reset() { root=0; file=0; fix=0 }
  BEGIN { reset(); b=0; bad=0 }
  /^\[RCA\]/       { if (b >= 1 && (!root || !file || !fix)) { print "block " b ": missing fields"; bad=1 } ; b++; reset(); next }
  /^- Root cause: ./   { root=1; next }
  /^- Failing file: ./ { file=1; next }
  /^- Fix: ./          { fix=1; next }
  END {
    if (b != total) { print "unbalanced [RCA]/[END RCA] markers"; exit 1 }
    if (b >= 1 && (!root || !file || !fix)) { print "block " b ": missing fields"; exit 1 }
    if (bad) exit 1
  }
' "$INPUT" || fail "RCA block missing required '- Root cause:'/'- Failing file:'/'- Fix:'"

exit 0
