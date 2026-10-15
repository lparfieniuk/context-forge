#!/usr/bin/env bash
# tools/shadow-lookup.sh — Symbol → file path TSV lookup from manifest
# Port from ai-system; adapted for context-forge
# Usage: shadow-lookup.sh --symbol <symbol> [--repo <repo>] [--kind <kind>]
# Output: TSV (symbol | kind | file | repo)
set -euo pipefail

# Parse args
_SYMBOL=""
_REPO=""
_KIND=""
_TEXT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: shadow-lookup.sh --symbol <symbol> [--repo <repo>] [--kind <kind>] [--text]

Look up a symbol in the lightweight shadow manifest.
Auto-detects IDE (.claude or .cursor) for manifest location.
--text: literal source matches in the current repo, only below 30 source files.
Text matches include references; they are NOT declaration or kind lookup.

Output: TSV (symbol | kind | file | repo)

Examples:
  shadow-lookup.sh --symbol AuthService
  shadow-lookup.sh --symbol BillingFacade --kind class
  shadow-lookup.sh --symbol createUser --kind function --repo auth
EOF
      exit 0
      ;;
    --text)
      _TEXT=true
      shift
      ;;
    --symbol|--repo|--kind)
      if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        echo "ERROR: $1 requires a value" >&2
        exit 1
      fi
      case "$1" in
    --symbol)
      _SYMBOL="$2"
      shift 2
      ;;
    --repo)
      _REPO="$2"
      shift 2
      ;;
    --kind)
      _KIND="$2"
      shift 2
      ;;
      esac
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

SYMBOL="$_SYMBOL"

if [[ -z "$SYMBOL" ]]; then
  echo "ERROR: --symbol required"
  exit 1
fi

if [[ "$SYMBOL" == *$'\t'* || "$SYMBOL" == *$'\n'* || "$SYMBOL" == *$'\r'* ]]; then
  echo "ERROR: --symbol must fit one TSV field" >&2
  exit 1
fi

if $_TEXT; then
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  NAME=$(basename "$ROOT")
  if [[ -n "$_KIND" || ( -n "$_REPO" && "$_REPO" != "$NAME" ) ]]; then
    echo "ERROR: --text cannot filter declaration kinds or search a different repo" >&2
    exit 1
  fi
  if [[ "$NAME" == *$'\t'* || "$NAME" == *$'\n'* || "$NAME" == *$'\r'* ]]; then
    echo "ERROR: repository name must fit one TSV field" >&2
    exit 1
  fi
  SCRATCH=$(mktemp -d)
  trap 'rm -rf "$SCRATCH"' EXIT
  # NUL-separated paths preserve spaces; ignore rules exclude dependencies — also outside a git
  # repo (`--no-require-git`), or a non-git dir with an ignored node_modules trips the 30-file cap.
  if rg --files --no-require-git -0 -g '*.{ts,tsx,js,jsx,mjs,cjs,py,php}' "$ROOT" > "$SCRATCH/files"; then
    :
  else
    status=$?
    [[ "$status" -eq 1 ]] || exit "$status"
  fi
  FILES=()
  while IFS= read -r -d '' file; do
    FILES+=("$file")
    if [[ ${#FILES[@]} -ge 30 ]]; then
      echo "ERROR: --text is limited to fewer than 30 source files; use indexed lookup or focused rg" >&2
      exit 1
    fi
  done < "$SCRATCH/files"
  if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "ERROR: No source files to search" >&2
    exit 1
  fi
  if rg -l -0 -F -- "$SYMBOL" "${FILES[@]}" > "$SCRATCH/matches"; then
    :
  else
    status=$?
    if [[ "$status" -eq 1 ]]; then echo "ERROR: No text matches for '$SYMBOL'" >&2; fi
    exit "$status"
  fi
  : > "$SCRATCH/result"
  while IFS= read -r -d '' file; do
    file=${file#"$ROOT/"}
    if [[ "$file" == *$'\t'* || "$file" == *$'\n'* || "$file" == *$'\r'* ]]; then
      echo "ERROR: matched path cannot be represented as TSV" >&2
      exit 1
    fi
    printf '%s\ttext-match\t%s\t%s\n' "$SYMBOL" "$file" "$NAME" >> "$SCRATCH/result"
  done < "$SCRATCH/matches"
  if [[ $(wc -c < "$SCRATCH/result") -gt 3000 ]]; then
    echo "ERROR: text matches exceed 3000 bytes; narrow the symbol or use focused rg" >&2
    exit 1
  fi
  echo "Text matches only, not declarations; inspect the returned files." >&2
  cat "$SCRATCH/result"
  exit 0
fi

# Auto-detect IDE
IDE_DIR=".claude"
if [[ ! -d ".claude" ]] && [[ -d ".cursor" ]]; then
  IDE_DIR=".cursor"
fi

# Detect repo. Defaulting to "context-forge" made every lookup in a foreign
# checkout miss — the manifest refresh-manifest.sh writes is named after the repo
# you are standing in.
REPO="${_REPO:-$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")}"

# Manifest path
MANIFEST_PATH="$IDE_DIR/shadow/$REPO/_manifest.lightweight.yaml"

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "ERROR: manifest not found at $MANIFEST_PATH"
  echo "HINT: Run 'bash core/scripts/tools/refresh-manifest.sh' to generate"
  echo "HINT: For fewer than 30 source files, use --text for literal matches without an index"
  exit 1
fi

# Search the manifest and emit the documented TSV: symbol<TAB>kind<TAB>file<TAB>repo.
# The previous `rg "kind:|file:|repo:" -o` printed the bare field labels — the
# pattern captured no values — so every successful lookup returned three useless
# lines. One awk pass over the entry blocks instead.
RESULT=$(awk -v want="$SYMBOL" -v kindf="$_KIND" '
  /^  - symbol:/ { sym=$3; kind=""; file=""; repo=""; next }
  /^    kind:/   { kind=$2; next }
  /^    file:/   { file=$2; next }
  /^    repo:/ {
    repo=$2
    if (sym == want && (kindf == "" || kind == kindf))
      printf "%s\t%s\t%s\t%s\n", sym, kind, file, repo
    sym=""
  }
' "$MANIFEST_PATH")

if [[ -z "$RESULT" ]]; then
  if [[ -n "$_KIND" ]]; then
    echo "ERROR: symbol '$SYMBOL' (kind: $_KIND) not found in $MANIFEST_PATH"
  else
    echo "ERROR: symbol '$SYMBOL' not found in $MANIFEST_PATH"
  fi
  exit 1
fi

printf '%s\n' "$RESULT"
