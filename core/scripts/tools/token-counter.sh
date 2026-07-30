#!/usr/bin/env bash
# tools/token-counter.sh — Estimate token count (1 token ≈ 4 chars)
# Usage: token-counter.sh --file <path> | --dir <path> | --rules
# Output: TSV (path | char_count | estimated_tokens)
set -euo pipefail

# Parse args
_FILE=""
_DIR=""
_RULES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: token-counter.sh [--file <path> | --dir <path> | --rules]

Estimate token count from source files.
Simple formula: 1 token ≈ 4 characters

Options:
  --file <path>    — Count single file
  --dir <path>     — Count all files in directory
  --rules          — Count all rule tokens in .claude/rules/

Output:
  TSV format: path | char_count | estimated_tokens

Examples:
  token-counter.sh --file src/auth.service.ts
  token-counter.sh --dir libs/auth/src
  token-counter.sh --rules
EOF
      exit 0
      ;;
    --file)
      _FILE="$2"
      shift 2
      ;;
    --dir)
      _DIR="$2"
      shift 2
      ;;
    --rules)
      _RULES=true
      shift
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

count_file_tokens() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  local char_count
  char_count=$(wc -c < "$file" | tr -d ' ')

  local token_estimate=$((char_count / 4))

  echo "$file	$char_count	$token_estimate"
}

count_dir_tokens() {
  local dir="$1"

  if [[ ! -d "$dir" ]]; then
    return 1
  fi

  local total_chars=0
  local file_count=0

  # Find all source files (exclude node_modules, dist, etc.)
  while IFS= read -r file; do
    local char_count
    char_count=$(wc -c < "$file" | tr -d ' ')
    total_chars=$((total_chars + char_count))
    file_count=$((file_count + 1))

    # Output per-file estimate
    local token_estimate=$((char_count / 4))
    echo "$file	$char_count	$token_estimate"
  done < <(find "$dir" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.tsx" -o -name "*.jsx" \) \
    ! -path "*/node_modules/*" ! -path "*/dist/*" ! -path "*/.git/*" 2>/dev/null)

  # Summary line
  echo ""
  echo "=== TOTAL ===" >&2
  echo "Files: $file_count" >&2
  echo "Characters: $total_chars" >&2
  echo "Estimated tokens: $((total_chars / 4))" >&2
}

count_rules_tokens() {
  local total=0
  echo "=== RULE TOKEN COUNTS ==="
  echo ""

  for rule_file in .claude/rules/*.md; do
    [[ ! -f "$rule_file" ]] && continue

    local char_count
    char_count=$(wc -c < "$rule_file" | tr -d ' ')
    local token_estimate=$((char_count / 4))
    total=$((total + token_estimate))

    echo "$(basename "$rule_file")	$char_count	$token_estimate"
  done

  echo ""
  echo "=== TOTAL RULE TOKENS: $total ==="
}

if [[ "$_RULES" == "true" ]]; then
  count_rules_tokens

elif [[ -n "$_FILE" ]]; then
  count_file_tokens "$_FILE"

elif [[ -n "$_DIR" ]]; then
  count_dir_tokens "$_DIR"

else
  echo "ERROR: --file, --dir, or --rules required"
  exit 1
fi
