#!/usr/bin/env bash
# tools/refresh-manifest.sh — Regenerate lightweight shadow manifest
# Usage: refresh-manifest.sh [--repo <name>] [--ide-dir <dir>]
# Creates: <IDE_DIR>/shadow/<repo>/_manifest.lightweight.yaml
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Parse args
_REPO=""
_IDE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: refresh-manifest.sh [--repo <name>] [--ide-dir <dir>]

Regenerate lightweight shadow manifest for symbol lookup.
Reads manifest-repos.json to find target repositories, scans each one,
and generates lightweight manifests for symbol lookup.

Options:
  --repo <name>     — Regenerate for specific repository only
  --ide-dir <dir>   — IDE directory (.claude or .cursor, auto-detected)

Output:
  <IDE_DIR>/shadow/<repo>/_manifest.lightweight.yaml (per repo)

Examples:
  refresh-manifest.sh
  refresh-manifest.sh --repo my-workspace
  refresh-manifest.sh --ide-dir .claude

Notes:
  - Reads config/manifest-repos.json relative to plugin root
  - Dual-writes to both .claude/shadow/ and .cursor/shadow/ when both exist
  - If manifest-repos.json missing, falls back to scanning shadow dirs
EOF
      exit 0
      ;;
    --repo)
      _REPO="$2"
      shift 2
      ;;
    --ide-dir)
      _IDE_DIR="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

# Auto-detect IDE if not specified
IDE_DIRS=()
if [[ -n "$_IDE_DIR" ]]; then
  IDE_DIRS=("$_IDE_DIR")
else
  if [[ -d ".claude" ]]; then
    IDE_DIRS+=(".claude")
  fi
  if [[ -d ".cursor" ]]; then
    IDE_DIRS+=(".cursor")
  fi

  if [[ ${#IDE_DIRS[@]} -eq 0 ]]; then
    echo "ERROR: IDE directory not found (.claude or .cursor)"
    exit 1
  fi
fi

# Function to generate manifest for a single repo
generate_manifest_for_repo() {
  local repo_name="$1"
  local repo_path="$2"
  local scan_paths="$3"
  local epoch_ts=$(date +%s)

  echo "  Scanning repo: $repo_name at $repo_path"

  # Iterate over each IDE dir and write manifest
  for ide_dir in "${IDE_DIRS[@]}"; do
    MANIFEST_DIR="$ide_dir/shadow/$repo_name"
    MANIFEST_FILE="$MANIFEST_DIR/_manifest.lightweight.yaml"

    mkdir -p "$MANIFEST_DIR"

    {
      echo "metadata:"
      echo "  generated: $epoch_ts"
      echo "  repo: $repo_name"
      echo "  scanned_files: 0"
      echo "symbols:"
      echo ""

      # Process each scan path
      if [[ -z "$scan_paths" ]]; then
        scan_paths="."
      fi

      # Replace comma-separated paths with space-separated
      scan_paths="${scan_paths//,/ }"

      symbol_count=0
      for scan_path in $scan_paths; do
        if [[ ! -d "$repo_path/$scan_path" ]]; then
          continue
        fi

        # Find all TypeScript/JavaScript files in this repo path
        find "$repo_path/$scan_path" -type f \( -name "*.ts" -o -name "*.js" \) \
          ! -path "*/node_modules/*" \
          ! -path "*/dist/*" \
          ! -path "*/.git/*" \
          ! -name "*.test.*" \
          ! -name "*.spec.*" 2>/dev/null | \
        while read -r file; do
          # Extract exports
          rg "^export\s+(class|interface|function|const|type|enum)\s+(\w+)" "$file" -r '$1|$2' 2>/dev/null | \
          while IFS='|' read -r kind name; do
            [[ -z "$name" ]] && continue

            # Normalize kind
            case "$kind" in
              class) kind="class" ;;
              interface) kind="interface" ;;
              function) kind="function" ;;
              const) kind="const" ;;
              type) kind="type" ;;
              enum) kind="enum" ;;
            esac

            # Relative path from repo root
            rel_file="${file#$repo_path/}"

            echo "  - symbol: $name"
            echo "    kind: $kind"
            echo "    file: $rel_file"
            echo "    repo: $repo_name"
            echo ""

            symbol_count=$((symbol_count + 1))
          done
        done
      done

      # Update scanned_files count at end (approximate)
      echo "# Total symbols: $symbol_count"
    } > "$MANIFEST_FILE"

    SYMBOL_COUNT=$(rg -c "^\s+- symbol:" "$MANIFEST_FILE" 2>/dev/null || echo 0)
    echo "    → $ide_dir/shadow/$repo_name/_manifest.lightweight.yaml ($SYMBOL_COUNT symbols)"
  done
}

# Read manifest-repos.json if it exists
CONFIG_FILE="$PLUGIN_ROOT/config/manifest-repos.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: config/manifest-repos.json not found at $CONFIG_FILE"
  echo ""
  echo "To use refresh-manifest, create config/manifest-repos.json with this structure:"
  echo '{'
  echo '  "repos": ['
  echo '    {"name": "my-workspace", "rel_path": "../../my-workspace", "paths": ["libs/", "apps/"]}'
  echo '  ]'
  echo '}'
  exit 1
fi

echo "=== REFRESH MANIFEST ==="
echo "Config: $CONFIG_FILE"
echo ""

# Parse JSON and generate manifests
# If jq is available, use it; otherwise use rg
if command -v jq &>/dev/null; then
  repos_json=$(jq -r '.repos[]' "$CONFIG_FILE")
  while IFS= read -r repo_entry; do
    if [[ -z "$repo_entry" ]]; then
      continue
    fi

    repo_name=$(echo "$repo_entry" | jq -r '.name')
    rel_path=$(echo "$repo_entry" | jq -r '.rel_path')
    paths=$(echo "$repo_entry" | jq -r '.paths | join(",")')

    # If --repo specified and doesn't match, skip
    if [[ -n "$_REPO" && "$_REPO" != "$repo_name" ]]; then
      continue
    fi

    # Resolve relative path
    repo_path="$PLUGIN_ROOT/$rel_path"
    if [[ ! -d "$repo_path" ]]; then
      echo "WARNING: Repository path not found: $repo_path"
      continue
    fi

    generate_manifest_for_repo "$repo_name" "$repo_path" "$paths"
  done <<< "$(jq -c '.repos[]' "$CONFIG_FILE")"
else
  # Fallback: parse with rg and basic string manipulation
  # Extract repo names with rg
  repo_names=$(rg '"name":\s*"([^"]+)"' "$CONFIG_FILE" -r '$1')

  while IFS= read -r repo_name; do
    [[ -z "$repo_name" ]] && continue

    # If --repo specified and doesn't match, skip
    if [[ -n "$_REPO" && "$_REPO" != "$repo_name" ]]; then
      continue
    fi

    # Extract paths for this repo using rg
    rel_path=$(rg "\"name\":\s*\"$repo_name\".*?\"rel_path\":\s*\"([^\"]+)\"" "$CONFIG_FILE" -A 2 -r '$1' | head -1)
    paths=$(rg "\"name\":\s*\"$repo_name\".*?\"paths\":\s*\[(.*?)\]" "$CONFIG_FILE" -r '$1' | head -1 | tr -d '", ')

    # Resolve relative path
    repo_path="$PLUGIN_ROOT/$rel_path"
    if [[ ! -d "$repo_path" ]]; then
      echo "WARNING: Repository path not found: $repo_path"
      continue
    fi

    generate_manifest_for_repo "$repo_name" "$repo_path" "$paths"
  done <<< "$repo_names"
fi

echo ""
echo "=== DONE REFRESH MANIFEST ==="
