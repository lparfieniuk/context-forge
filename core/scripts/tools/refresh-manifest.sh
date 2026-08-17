#!/usr/bin/env bash
# tools/refresh-manifest.sh — Regenerate lightweight shadow manifest
# Usage: refresh-manifest.sh [--repo <name>] [--ide-dir <dir>]
# Creates: <IDE_DIR>/shadow/<repo>/_manifest.lightweight.yaml
set -euo pipefail

# This script lives at <plugin-root>/core/scripts/tools/ — three levels down.
# `../..` lands on core/ and made every config lookup miss silently.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

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
    # A repo the user opened for the first time has neither dir. Erroring here
    # made the script unusable in exactly the case it exists for. Rule 002's own
    # detection table already prescribes a fallback; follow it.
    IDE_DIRS+=(".claude")
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

    # Scan paths: comma-separated, empty means whole repo.
    if [[ -z "$scan_paths" ]]; then
      scan_paths="."
    fi
    local -a SCAN_ARGS=()
    local sp
    for sp in ${scan_paths//,/ }; do
      [[ -d "$repo_path/$sp" ]] && SCAN_ARGS+=("$repo_path/$sp")
    done
    if [[ ${#SCAN_ARGS[@]} -eq 0 ]]; then
      echo "    → no existing scan path under $repo_path — skipped"
      continue
    fi

    # One rg pass per language instead of find + per-file rg. rg already honours
    # .gitignore, so node_modules/dist/.git need no exclusion list, and the count
    # is computed from the emitted file rather than a variable that lived in a
    # pipeline subshell (the old `symbol_count` was always 0).
    local BODY
    BODY=$(
      {
        rg --no-heading --no-line-number -o \
          -g '!*.test.*' -g '!*.spec.*' -g '*.{ts,tsx,js,jsx,mjs}' \
          -r 'CF$1|CF$2' \
          '^export\s+(?:default\s+)?(class|interface|function|const|type|enum)\s+(\w+)' \
          "${SCAN_ARGS[@]}" 2>/dev/null || true
        rg --no-heading --no-line-number -o \
          -g '!test_*' -g '!*_test.py' -g '*.py' \
          -r 'CF$1|CF$2' \
          '^(class|def)\s+(\w+)' \
          "${SCAN_ARGS[@]}" 2>/dev/null || true
        rg --no-heading --no-line-number -o \
          -g '*.php' -r 'CF$1|CF$2' \
          '^\s*(?:abstract\s+|final\s+)?(class|interface|trait|function)\s+(\w+)' \
          "${SCAN_ARGS[@]}" 2>/dev/null || true
      } | awk -v repo="$repo_name" -v root="$repo_path/" '
        {
          # rg emits "<path>:CF<kind>|CF<name>". The payload is always the tail,
          # so scan for the LAST marker: a path that itself contains ":CF"
          # (legal on Unix) would otherwise split in the wrong place and yield a
          # truncated path with the rest of it glued onto the kind.
          i = 0
          for (k = index($0, ":CF"); k > 0; k = index(substr($0, i + 1), ":CF")) {
            i = i + k
            if (i + 3 > length($0)) break
          }
          if (i == 0) next
          file = substr($0, 1, i - 1)
          rest = substr($0, i + 3)
          j = index(rest, "|CF")
          if (j == 0) next
          kind = substr(rest, 1, j - 1)
          name = substr(rest, j + 3)
          if (name == "") next
          if (kind == "def") kind = "function"
          sub("^" root, "", file)
          sub("^\\./", "", file)
          printf "  - symbol: %s\n    kind: %s\n    file: %s\n    repo: %s\n\n", name, kind, file, repo
        }
      '
    )
    local symbol_count
    symbol_count=$(printf '%s\n' "$BODY" | rg -c '^  - symbol:' || echo 0)
    local file_count
    # `|| true`: rg exits 1 on zero matches and pipefail would abort the script
    # on a legitimately symbol-free repo.
    file_count=$( { printf '%s\n' "$BODY" | rg '^    file:' || true; } | sort -u | rg -c . || echo 0)

    {
      # ISO-8601 UTC — session-start.sh parses this with
      # `date -j -f "%Y-%m-%dT%H:%M:%SZ"`. Writing raw epoch here made every
      # manifest parse as epoch 0 and report "✗ BROKEN" regardless of age.
      echo "metadata:"
      echo "  generated: \"$(date -u -r "$epoch_ts" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)\""
      echo "  repo: $repo_name"
      echo "  scanned_files: $file_count"
      echo "  total_symbols: $symbol_count"
      echo "symbols:"
      echo ""
      printf '%s\n' "$BODY"
    } > "$MANIFEST_FILE"

    SYMBOL_COUNT=$(rg -c "^\s+- symbol:" "$MANIFEST_FILE" 2>/dev/null || echo 0)
    echo "    → $ide_dir/shadow/$repo_name/_manifest.lightweight.yaml ($SYMBOL_COUNT symbols)"

    # This drops a generated file into someone's working tree. Say so when it
    # would show up as untracked — a manifest committed by accident is noise in
    # every future diff, and silence is how that happens.
    if git -C "$(dirname "$MANIFEST_FILE")" rev-parse --git-dir >/dev/null 2>&1; then
      if ! git check-ignore -q "$MANIFEST_FILE" 2>/dev/null; then
        echo "    ⚠ not gitignored — add '$ide_dir/shadow/' to .gitignore"
      fi
    fi
  done
}

# Read manifest-repos.json if it exists
CONFIG_FILE="$PLUGIN_ROOT/config/manifest-repos.json"

# Count configured repos. A missing file and an empty `repos: []` are the same
# situation for us: nothing to scan from config.
CONFIGURED=0
if [[ -f "$CONFIG_FILE" ]]; then
  if command -v jq &>/dev/null; then
    CONFIGURED=$(jq '.repos | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
  else
    CONFIGURED=$(rg -c '"name":' "$CONFIG_FILE" 2>/dev/null || echo 0)
  fi
fi

echo "=== REFRESH MANIFEST ==="

# Foreign-repo path: the plugin is installed globally, so a checkout the user
# opened today has no entry in config/manifest-repos.json and never will. Rule
# 002 tells the agent to run this immediately when a manifest is missing — that
# instruction was unrunnable while the only source of targets was that config.
# Default to the repo we are standing in.
if [[ "$CONFIGURED" -eq 0 || -n "$_REPO" ]] && [[ -z "${CF_CONFIG_ONLY:-}" ]]; then
  CWD_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  CWD_NAME=$(basename "$CWD_ROOT")
  if [[ "$CONFIGURED" -eq 0 ]] || [[ "$_REPO" == "$CWD_NAME" ]]; then
    echo "Target: current repo ($CWD_NAME at $CWD_ROOT)"
    echo ""
    generate_manifest_for_repo "$CWD_NAME" "$CWD_ROOT" ""
    echo ""
    echo "=== DONE REFRESH MANIFEST ==="
    exit 0
  fi
fi

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
