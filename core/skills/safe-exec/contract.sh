#!/usr/bin/env bash
# contract.sh — machine-checkable output contract for the safe-exec skill.
#
# Usage: contract.sh <sample-file>   (or sample on stdin)
# Exit 0 = output conforms to the [SAFE-EXEC] envelope; exit 1 = violation.
#
# Contract (from core/skills/safe-exec/SKILL.md Output Format):
#   [SAFE-EXEC] opens, [END SAFE-EXEC] closes
#   - Command: <cmd>          required
#   - Exit code: <n>          required
#   - Summary/Output body     at least one non-header line

set -euo pipefail

INPUT="${1:-/dev/stdin}"
[[ -f "$INPUT" ]] || { echo "contract: no such file: $INPUT" >&2; exit 1; }

fail() { echo "safe-exec contract violation: $1" >&2; exit 1; }

grep -q '^\[SAFE-EXEC\]' "$INPUT" || fail "missing opening [SAFE-EXEC] marker"
grep -q '^\[END SAFE-EXEC\]' "$INPUT" || fail "missing closing [END SAFE-EXEC] marker"
grep -q '^- Command: .' "$INPUT" || fail "missing '- Command:' field"
grep -q '^- Exit code: ' "$INPUT" || fail "missing '- Exit code:' field"

# At least one content line between the markers (summary or captured output).
sed -n '/^\[SAFE-EXEC\]/,/^\[END SAFE-EXEC\]/p' "$INPUT" \
  | grep -cvE '^(\[SAFE-EXEC\]|\[END SAFE-EXEC\]|[[:space:]]*)$' | grep -qv '^0$' \
  || fail "empty envelope — no summary or output between markers"

exit 0
