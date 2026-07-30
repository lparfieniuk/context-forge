#!/usr/bin/env bash
# lib/rg-helpers.sh — Shared ripgrep wrappers for context-forge
# Functions: rg_count, rg_files, rg_context, rg_first_match, rg_dedup_tsv
set -euo pipefail

# rg_count(pattern, path) — Count matches (returns integer)
rg_count() {
  local pattern="$1"
  local path="${2:-.}"

  rg -c "$pattern" "$path" 2>/dev/null | rg -o '^\d+' | paste -sd+ | bc 2>/dev/null || echo "0"
}

# rg_files(pattern, path) — List matching files (one per line)
rg_files() {
  local pattern="$1"
  local path="${2:-.}"

  rg -l "$pattern" "$path" 2>/dev/null || echo ""
}

# rg_context(pattern, path, before, after) — Extract with context
# before: lines before (default 2)
# after: lines after (default 2)
rg_context() {
  local pattern="$1"
  local path="${2:-.}"
  local before="${3:-2}"
  local after="${4:-2}"

  rg -B "$before" -A "$after" "$pattern" "$path" 2>/dev/null || echo ""
}

# rg_first_match(pattern, path) — Return first match only (no context)
rg_first_match() {
  local pattern="$1"
  local path="${2:-.}"

  rg -m1 "$pattern" "$path" 2>/dev/null || echo ""
}

# rg_extract_group(pattern, group_num, path) — Extract capture group
# group_num: 1-indexed capture group number
rg_extract_group() {
  local pattern="$1"
  local group_num="${2:-1}"
  local path="${3:-.}"

  rg "$pattern" -r "\$$group_num" "$path" 2>/dev/null || echo ""
}

# rg_dedup_tsv() — Remove duplicate TSV lines (by first column)
# Input: stdin (TSV format)
# Output: TSV with duplicates removed (keeps first occurrence)
rg_dedup_tsv() {
  # Use awk to track first occurrence of each key (column 1)
  awk -F '\t' '!seen[$1]++' || echo ""
}

# rg_tsv_column(column_num) — Extract single column from TSV
# column_num: 1-indexed column number
# Input: stdin (TSV format)
# Output: values from specified column
rg_tsv_column() {
  local column_num="${1:-1}"

  awk -F '\t' "{print \$$column_num}" || echo ""
}

# rg_parallel_scan(pattern, paths...) — Scan multiple paths in parallel
# Returns: file:line matches
rg_parallel_scan() {
  local pattern="$1"
  shift
  local -a paths=("$@")

  for path in "${paths[@]}"; do
    rg -n "$pattern" "$path" 2>/dev/null &
  done
  wait
}

# rg_multiline(pattern, path) — Search with multiline mode (. matches newline)
rg_multiline() {
  local pattern="$1"
  local path="${2:-.}"

  rg -U "$pattern" "$path" 2>/dev/null || echo ""
}

# rg_type_filter(file_type, pattern, path) — Search within specific file type
# file_type: ts, js, py, php, etc.
rg_type_filter() {
  local file_type="$1"
  local pattern="$2"
  local path="${3:-.}"

  rg --type "$file_type" "$pattern" "$path" 2>/dev/null || echo ""
}

# rg_invert_match(pattern, path) — Return lines NOT matching pattern
rg_invert_match() {
  local pattern="$1"
  local path="${2:-.}"

  rg -v "$pattern" "$path" 2>/dev/null || echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Help text
  cat <<'EOF'
rg-helpers.sh — Shared ripgrep wrappers for context-forge

Functions:
  rg_count(pattern, path)            — Count matches
  rg_files(pattern, path)            — List matching files
  rg_context(pattern, path, B, A)    — Extract with context
  rg_first_match(pattern, path)      — Return first match only
  rg_extract_group(pattern, group, path) — Extract capture group
  rg_dedup_tsv()                     — Dedup TSV by first column
  rg_tsv_column(col_num)             — Extract single TSV column
  rg_parallel_scan(pattern, paths...) — Scan multiple paths in parallel
  rg_multiline(pattern, path)        — Search with multiline mode
  rg_type_filter(type, pattern, path) — Search within file type
  rg_invert_match(pattern, path)     — Return non-matching lines

Usage:
  source lib/rg-helpers.sh
  count=$(rg_count "export class" libs/auth/src)
  files=$(rg_files "TODO" .)
EOF
  exit 0
fi
