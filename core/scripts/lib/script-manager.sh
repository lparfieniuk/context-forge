#!/usr/bin/env bash
# lib/script-manager.sh — Script routing and discovery for context-forge
# Functions: resolve_script, list_scripts, script_info
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# resolve_script(script_id) — Look up script path from _index.yaml
# Returns: path relative to SCRIPT_DIR
resolve_script() {
  local script_id="$1"

  if [[ ! -f "$SCRIPT_DIR/_index.yaml" ]]; then
    echo "ERROR: _index.yaml not found at $SCRIPT_DIR/_index.yaml" >&2
    return 1
  fi

  # Use rg to find script entry and extract path
  local script_entry
  script_entry=$(rg "id:\s*${script_id}$" -A 3 "$SCRIPT_DIR/_index.yaml" 2>/dev/null) || {
    echo "ERROR: script '$script_id' not found in _index.yaml" >&2
    return 1
  }

  # Extract 'path' field from the entry
  local path
  path=$(echo "$script_entry" | rg "^\s*path:\s*(.+)$" -r '$1' 2>/dev/null | head -1)

  if [[ -z "$path" ]]; then
    echo "ERROR: no path found for script '$script_id'" >&2
    return 1
  fi

  echo "$path"
}

# list_scripts() — List all available scripts with ID and description
# Output: TSV (id | path | description)
list_scripts() {
  if [[ ! -f "$SCRIPT_DIR/_index.yaml" ]]; then
    echo "ERROR: _index.yaml not found" >&2
    return 1
  fi

  # Parse _index.yaml for script entries
  # Format: id, path, description (if present)
  rg -A 2 "^\s*-\s+id:" "$SCRIPT_DIR/_index.yaml" 2>/dev/null | \
    rg -B 1 -A 1 "id:|path:" | \
    rg "id:|path:|description:" | \
    paste -d'\t' - - - 2>/dev/null || echo ""
}

# script_exists(script_id) — Check if script exists in _index.yaml
script_exists() {
  local script_id="$1"

  rg "id:\s*${script_id}$" "$SCRIPT_DIR/_index.yaml" >/dev/null 2>&1
}

# search_scripts(keyword) — Search scripts by keyword in description or ID
# Returns: TSV (id | description)
search_scripts() {
  local keyword="$1"

  if [[ ! -f "$SCRIPT_DIR/_index.yaml" ]]; then
    return 1
  fi

  rg -i "id:|description:" "$SCRIPT_DIR/_index.yaml" 2>/dev/null | \
    rg -i "$keyword" || echo ""
}

# script_info(script_id) — Get full metadata for a script
# Output: YAML block for the script entry
script_info() {
  local script_id="$1"

  if [[ ! -f "$SCRIPT_DIR/_index.yaml" ]]; then
    return 1
  fi

  rg -A 10 "id:\s*${script_id}$" "$SCRIPT_DIR/_index.yaml" 2>/dev/null || {
    echo "ERROR: script '$script_id' not found" >&2
    return 1
  }
}

# get_script_path_absolute(script_id) — Get absolute path to script
get_script_path_absolute() {
  local script_id="$1"
  local relative_path

  relative_path=$(resolve_script "$script_id") || return 1

  # Make absolute relative to SCRIPT_DIR
  if [[ "$relative_path" == /* ]]; then
    echo "$relative_path"
  else
    echo "$SCRIPT_DIR/$relative_path"
  fi
}

# validate_scripts() — Check all scripts in _index.yaml exist on disk
validate_scripts() {
  local issues=0

  if [[ ! -f "$SCRIPT_DIR/_index.yaml" ]]; then
    echo "ERROR: _index.yaml not found" >&2
    return 1
  fi

  # Extract all 'path' values
  local paths
  paths=$(rg "^\s*path:\s*(.+)$" -r '$1' "$SCRIPT_DIR/_index.yaml" 2>/dev/null) || true

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue

    # Make absolute
    local abs_path="$path"
    if [[ ! "$abs_path" == /* ]]; then
      abs_path="$SCRIPT_DIR/$abs_path"
    fi

    if [[ ! -f "$abs_path" ]]; then
      echo "MISSING: $path"
      ((issues++))
    fi
  done <<<"$paths"

  if [[ $issues -gt 0 ]]; then
    echo "ERROR: $issues script(s) referenced in _index.yaml but missing on disk" >&2
    return 1
  fi

  echo "OK: All scripts present"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Command-line interface
  case "${1:-help}" in
    resolve)
      resolve_script "${2:-}"
      ;;
    list)
      list_scripts
      ;;
    exists)
      script_exists "${2:-}" && echo "true" || echo "false"
      ;;
    search)
      search_scripts "${2:-}"
      ;;
    info)
      script_info "${2:-}"
      ;;
    abs-path)
      get_script_path_absolute "${2:-}"
      ;;
    validate)
      validate_scripts
      ;;
    --help|-h|help)
      cat <<'EOF'
script-manager.sh — Script routing and discovery

Commands:
  resolve <id>      — Get path for script by ID
  list              — List all scripts (TSV: id | path | description)
  exists <id>       — Check if script exists (exit 0/1)
  search <keyword>  — Search scripts by keyword
  info <id>         — Get full metadata for script
  abs-path <id>     — Get absolute path to script
  validate          — Validate all scripts exist

Usage:
  source lib/script-manager.sh
  path=$(resolve_script "extract-signatures")
  bash "$SCRIPT_DIR/$path" --help
EOF
      exit 0
      ;;
    *)
      echo "Unknown command: $1" >&2
      exit 1
      ;;
  esac
fi
