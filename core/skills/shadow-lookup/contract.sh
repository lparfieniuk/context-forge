#!/usr/bin/env bash
# contract.sh — machine-checkable output contract for the shadow-lookup skill.
#
# Usage: contract.sh <sample-file>   (or sample on stdin)
# Exit 0 = output conforms to the lookup TSV; exit 1 = violation.
#
# Contract (from core/skills/shadow-lookup/SKILL.md Output Format):
#   At least one row; every non-empty line is 4 tab-separated fields:
#     symbol_name <TAB> kind <TAB> file_path <TAB> repo
#   kind ∈ class | interface | enum | function | type | const | variable | text-match

set -euo pipefail

INPUT="${1:-/dev/stdin}"
[[ -f "$INPUT" ]] || { echo "contract: no such file: $INPUT" >&2; exit 1; }

fail() { echo "shadow-lookup contract violation: $1" >&2; exit 1; }

awk -F'\t' '
  /^[[:space:]]*$/ { next }
  { rows++ }
  NF != 4 { printf "line %d: expected 4 tab-separated fields, got %d\n", NR, NF; bad=1; next }
  $2 !~ /^(class|interface|enum|function|type|const|variable|text-match)$/ {
    printf "line %d: unknown kind %q\n", NR, $2; bad=1
  }
  END { exit (bad || !rows) ? 1 : 0 }
' "$INPUT" || fail "malformed TSV row(s)"

exit 0
