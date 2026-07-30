#!/usr/bin/env bash
# lib/yaml.sh — Minimal YAML helpers for context-forge
# Functions: yaml_get_value, yaml_append_entry, yaml_parse_key_value
# Uses pure bash + rg, no external YAML parser
set -euo pipefail

# yaml_get_value(file, key) — Extract value for a key from simple YAML
# Returns empty string if not found
yaml_get_value() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  # Use rg to find the key: pattern, extract value
  # Handle: key: value, key: |, key: >
  rg "^${key}:\s*(.+)$" "$file" -r '$1' 2>/dev/null | head -1 || echo ""
}

# yaml_append_entry(file, entry_yaml) — Append a YAML block to a file
# Assumes file exists and ends with newline
yaml_append_entry() {
  local file="$1"
  local entry="$2"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  echo "" >> "$file"
  echo "$entry" >> "$file"
}

# yaml_parse_key_value(line) — Parse a YAML key: value line
# Output: key\tvalue (TSV format)
yaml_parse_key_value() {
  local line="$1"

  # Match: key: value (handle quoted values, colons in values)
  echo "$line" | rg "^([a-zA-Z_][a-zA-Z0-9_]*):\s*(.+)$" -r '$1\t$2' 2>/dev/null || echo ""
}

# yaml_escape_value(string) — Escape special YAML characters
# Wraps in quotes if needed
yaml_escape_value() {
  local value="$1"

  # If contains special chars, wrap in quotes
  if echo "$value" | rg -q '[:"{}[\],&*#?@`|]'; then
    echo "\"${value//\"/\\\"}\""
  else
    echo "$value"
  fi
}

# yaml_section_exists(file, section_name) — Check if a top-level section exists
yaml_section_exists() {
  local file="$1"
  local section="$2"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  rg "^${section}:" "$file" >/dev/null 2>&1
}

# yaml_get_array(file, key) — Extract array values from YAML
# Returns one value per line
yaml_get_array() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  # Find the key, then extract all indented list items
  rg -A 100 "^${key}:" "$file" 2>/dev/null | rg "^\s*-\s+(.+)$" -r '$1' || echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Help text
  cat <<'EOF'
yaml.sh — Minimal YAML helpers for context-forge

Functions:
  yaml_get_value(file, key)          — Extract value for a key
  yaml_append_entry(file, entry)     — Append a YAML block
  yaml_parse_key_value(line)         — Parse key: value line
  yaml_escape_value(string)          — Escape special YAML characters
  yaml_section_exists(file, section) — Check if section exists
  yaml_get_array(file, key)          — Extract array values

Usage:
  source lib/yaml.sh
  value=$(yaml_get_value config.yaml some_key)
  yaml_append_entry config.yaml "new_key: new_value"
EOF
  exit 0
fi
