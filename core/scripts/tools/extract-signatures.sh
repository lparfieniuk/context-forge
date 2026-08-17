#!/usr/bin/env bash
# tools/extract-signatures.sh — Extract TypeScript/PHP method stubs from source file
# Port from ai-system; adapted for context-forge
# Usage: extract-signatures.sh --file <file_path>
# Output: Indented signature blocks and method list
set -euo pipefail

# Parse args
_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: extract-signatures.sh --file <file_path>

Extract exported TypeScript/JS symbols and method signatures from a source file.
Output: Indented signature blocks with line numbers and symbol types.

Examples:
  extract-signatures.sh --file src/auth/auth.service.ts
  extract-signatures.sh --file libs/billing/src/index.ts
EOF
      exit 0
      ;;
    --file)
      _FILE="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

FILE="$_FILE"

if [[ -z "$FILE" ]]; then
  echo "ERROR: --file required"
  echo "Usage: extract-signatures.sh --file <file_path>"
  exit 1
fi

# Resolve absolute path
if [[ ! "$FILE" = /* ]]; then
  FILE="$(pwd)/$FILE"
fi

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: file not found: $FILE"
  exit 1
fi

ISSUES=0
echo "=== EXTRACT SIGNATURES: $(basename "$FILE") ==="
echo ""

# Count lines to decide strategy
LINE_COUNT=$(wc -l < "$FILE" | tr -d ' ')

FILE_BYTES=$(wc -c < "$FILE" | tr -d ' ')

if [[ $LINE_COUNT -le 50 ]]; then
  BODY="## File ($LINE_COUNT lines) — reading directly
$(cat "$FILE")"
else
  # One pass over the top-level declarations, exported or not.
  #
  # This used to be three rg passes under three headings ("Exported top-level
  # symbols", "All top-level declarations", "Public class members") whose
  # matches almost entirely overlapped — the third pattern, an identifier
  # followed by `:` or `(`, matches most lines of most files. On a 3456-byte
  # module the tool emitted 4213 bytes: a signature extractor that cost more
  # than reading the source it was meant to replace.
  # TS/JS declarations, plus the PHP forms — `class`/`interface`/`trait`/
  # `function`, optionally preceded by a visibility or abstract/final modifier.
  # PHP was claimed as supported by the skill description, this script's own
  # header and the rule table, while the pattern only ever matched `export …`:
  # every PHP file produced an empty extraction.
  DECLS=$(rg -n "^(export )?(default )?(public |protected |private )?(abstract |final )?(static )?(async )?(class|interface|trait|enum|type|function|const|let|var) " "$FILE" 2>/dev/null || true)
  if [[ -z "$DECLS" ]]; then
    DECLS="  (none found)"
  fi

  BODY="## Top-level declarations

$DECLS"

  # Class members are only worth a section when the file declares a class.
  if rg -q "^\s*(export |default |abstract |final )*(class|trait) " "$FILE" 2>/dev/null; then
    # Both `|| true`s are load-bearing under `set -o pipefail`: rg exits 1 on
    # zero matches, so a class with no public members failed the assignment and
    # killed the script instead of printing the declarations it had.
    MEMBERS=$({ rg -n "^\s+(public |readonly |static |abstract |async |function )*[a-zA-Z_\$][a-zA-Z0-9_\$]*\s*[:\(]" "$FILE" 2>/dev/null || true; } \
      | { rg -v "(private |protected )" || true; } | head -40)
    # A plain `if`, not `[[ … ]] && …`: as the last command of this block the
    # && list's failure aborted the script under `set -e` on any class file
    # with no visible members.
    if [[ -n "$MEMBERS" ]]; then
      BODY="$BODY

## Public class members

$MEMBERS"
    fi
  fi

  DECOS=$(rg -n "^@(Component|Injectable|NgModule|Directive|Pipe|Input|Output|ViewChild|HostListener|Controller|Get|Post|Put|Delete)" "$FILE" 2>/dev/null | head -20 || true)
  if [[ -n "$DECOS" ]]; then
    BODY="$BODY

## Decorators

$DECOS"
  fi
fi

# The tool exists to cost less than reading the file. On a dense module that is
# nearly all declarations it cannot — and reprinting the source here would only
# add a header to it. Say so and send the caller to the file, which is the one
# answer that is both cheaper and correct.
BODY_BYTES=$(printf '%s' "$BODY" | wc -c | tr -d ' ')
if [[ $LINE_COUNT -gt 50 && $BODY_BYTES -ge $FILE_BYTES ]]; then
  BODY="## Extraction would cost more than the source ($BODY_BYTES B vs $FILE_BYTES B).
## Read $FILE directly — it is almost entirely declarations."
fi

printf '%s\n' "$BODY"

echo ""
echo "METRICS:"
echo "  issues=$ISSUES"
echo "  lines=$LINE_COUNT"
echo "=== DONE EXTRACT SIGNATURES ==="
