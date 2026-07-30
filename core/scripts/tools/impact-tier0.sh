#!/usr/bin/env bash
# tools/impact-tier0.sh — Quick heuristic helpers for impact analysis
# Tier 0: deterministic checks, no LLM needed
# Functions: is_api_boundary, quick_impact, has_tests
set -euo pipefail

# is_api_boundary(symbol, repo_root) — Check if symbol is exported from index/barrel file
# Returns: true/false
is_api_boundary() {
  local symbol="$1"
  local repo_root="${2:-.}"

  # Find index.ts files
  local index_files
  index_files=$(rg -l "^export.*$symbol" "$repo_root" 2>/dev/null | rg "index\." | head -5)

  if [[ -n "$index_files" ]]; then
    echo "true"
    return 0
  else
    echo "false"
    return 1
  fi
}

# quick_impact(symbol, repo_root) — Count importers of symbol
# Returns: integer (number of files importing symbol)
quick_impact() {
  local symbol="$1"
  local repo_root="${2:-.}"

  local count
  count=$(rg "import.*$symbol|from.*$symbol" "$repo_root" \
    --glob '!*.test.*' --glob '!*.spec.*' \
    2>/dev/null | wc -l)

  echo "$count"
}

# has_tests(file_path) — Check if file has corresponding test file
# Returns: true/false
has_tests() {
  local file="$1"

  # Resolve directory and base name
  local dir base
  dir=$(dirname "$file")
  base=$(basename "$file" | sed 's/\.[^.]*$//')

  # Look for *.test.ts, *.spec.ts, __tests__ dir
  if [[ -f "$dir/${base}.test.ts" ]] || \
     [[ -f "$dir/${base}.spec.ts" ]] || \
     [[ -f "$dir/__tests__/${base}.ts" ]] || \
     [[ -d "$dir/__tests__" ]]; then
    echo "true"
    return 0
  else
    echo "false"
    return 1
  fi
}

# is_high_volatility(symbol, repo_root) — Check if symbol changed frequently
# Returns: true/false (simplified: check git history)
is_high_volatility() {
  local symbol="$1"
  local repo_root="${2:-.}"

  # Count recent commits touching files with this symbol
  local commit_count
  commit_count=$(cd "$repo_root" && \
    git log --oneline --all -20 -- "$(rg -l "$symbol" . 2>/dev/null | head -1)" 2>/dev/null | wc -l)

  # If changed in last 20 commits, consider high volatility
  if [[ $commit_count -gt 5 ]]; then
    echo "true"
    return 0
  else
    echo "false"
    return 1
  fi
}

# get_importers(symbol, repo_root) — List files importing symbol
# Returns: list of file paths (one per line)
get_importers() {
  local symbol="$1"
  local repo_root="${2:-.}"

  rg "import.*$symbol|from.*\($symbol\)" "$repo_root" -l \
    --glob '!*.test.*' --glob '!*.spec.*' --glob '!node_modules/**' \
    2>/dev/null | sort -u
}

# estimate_blast_radius(symbol, repo_root) — Estimate scope of change impact
# Returns: Tier 0 | Tier 1 | Tier 2 | Tier 3
estimate_blast_radius() {
  local symbol="$1"
  local repo_root="${2:-.}"

  local importer_count
  local is_api
  local has_test

  importer_count=$(quick_impact "$symbol" "$repo_root")
  is_api=$(is_api_boundary "$symbol" "$repo_root")
  has_test=$(has_tests "$symbol")

  # Simple heuristic
  if [[ $importer_count -eq 0 ]]; then
    echo "Tier:0 — No importers, safe to modify"
    return 0
  elif [[ $importer_count -le 3 ]] && [[ "$is_api" == "false" ]]; then
    echo "Tier:1 — Internal use, <3 importers, narrow scope"
    return 0
  elif [[ $importer_count -le 10 ]] && [[ "$is_api" == "false" ]]; then
    echo "Tier:2 — Internal use, moderate spread (3-10 importers)"
    return 0
  elif [[ "$is_api" == "true" ]]; then
    echo "Tier:3 — API boundary, extensive impact potential"
    return 0
  else
    echo "Tier:2 — Moderate-to-high spread ($importer_count importers)"
    return 0
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Command-line interface
  case "${1:-help}" in
    --help|-h|help)
      cat <<'EOF'
impact-tier0.sh — Quick impact heuristics (Tier 0)

Functions:
  is_api_boundary <symbol> [repo] — Check if exported from index file
  quick_impact <symbol> [repo]    — Count files importing symbol
  has_tests <file>                — Check for test file
  is_high_volatility <symbol> [repo] — Check git history
  get_importers <symbol> [repo]   — List files importing symbol
  estimate_blast_radius <symbol> [repo] — Estimate change scope

Usage:
  source tools/impact-tier0.sh
  is_api=$(is_api_boundary "AuthService" .)
  count=$(quick_impact "BillingFacade" .)
  blast=$(estimate_blast_radius "createUser" .)

All functions return exit code 0/1 and echo result to stdout.
EOF
      exit 0
      ;;
    is_api_boundary)
      is_api_boundary "${2:-}" "${3:-.}"
      ;;
    quick_impact)
      quick_impact "${2:-}" "${3:-.}"
      ;;
    has_tests)
      has_tests "${2:-}"
      ;;
    is_high_volatility)
      is_high_volatility "${2:-}" "${3:-.}"
      ;;
    get_importers)
      get_importers "${2:-}" "${3:-.}"
      ;;
    estimate_blast_radius)
      estimate_blast_radius "${2:-}" "${3:-.}"
      ;;
    *)
      echo "Unknown command: $1"
      exit 1
      ;;
  esac
fi
