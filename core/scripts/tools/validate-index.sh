#!/usr/bin/env bash
# validate-index.sh — verify core/_index.yaml is consistent with the filesystem.
#
# Adapted from ai-system's validate-index.sh for ContextForge plugin structure.
#
# Checks:
#   1. source file exists
#   2. yaml file exists
#   3. script file exists (when declared)
#   4. installed_cursor path exists (DRIFT only — advisory)
#   5. installed_claude path exists (DRIFT only — advisory)
#
# Usage:
#   bash core/scripts/tools/validate-index.sh --plugin-root <path>
#
# Output (stdout):
#   ERROR lines  — files declared in _index.yaml but missing from disk
#   DRIFT lines  — installed paths not yet written (run npm run convert)
#   METRICS block — summary counts
#
# Exit code: 0 = clean (or errors-only acceptable), 1 = errors found

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: $(basename "$0") --plugin-root <path>"
  echo "  Verify core/_index.yaml is consistent with filesystem; reports ERROR/DRIFT lines"
  exit 0
fi

PLUGIN_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-root) PLUGIN_ROOT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Default to current directory if not specified
if [[ -z "$PLUGIN_ROOT" ]]; then
  PLUGIN_ROOT="$(pwd)"
fi

INDEX="$PLUGIN_ROOT/core/_index.yaml"
SCRIPTS_INDEX="$PLUGIN_ROOT/core/scripts/_index.yaml"

if [[ ! -f "$INDEX" ]]; then
  echo "ERROR: core/_index.yaml not found at $INDEX" >&2
  exit 1
fi

echo "=== VALIDATE INDEX ==="
echo "  plugin-root: $PLUGIN_ROOT"
echo "  index: $INDEX"
echo "  scripts-index: $SCRIPTS_INDEX"
echo ""

# Use a temp file to capture results and count properly
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

# Parse _index.yaml with awk — no yq dependency required
# Extracts key: value pairs per module block, resets on "- id:" line
awk '
  /^  - id:/ {
    if (id != "") flush()
    id = $NF; source = ""; yaml = ""; script = ""; icursor = ""; iclaude = ""
  }
  /^    source:/ { source = $NF }
  /^    yaml:/ { yaml = $NF }
  /^    script:/ { script = $NF }
  /^    installed_cursor:/ {
    v = $NF
    # skip null values
    if (v != "null") icursor = v
  }
  /^    installed_claude:/ {
    v = $NF
    # skip null values — an on-demand rule (activation != always) is
    # deliberately not installed into .claude/rules/; see convert.ts.
    if (v != "null") iclaude = v
  }
  END { if (id != "") flush() }

  function flush() {
    print "MODULE\t" id
    print "SOURCE\t" source
    print "YAML\t" yaml
    if (script != "") print "SCRIPT\t" script
    if (icursor != "") print "ICURSOR\t" icursor
    if (iclaude != "") print "ICLAUDE\t" iclaude
  }
' "$INDEX" > "$TMPFILE"

error_count=0
drift_count=0
checked_count=0
current_id=""

while IFS=$'\t' read -r key val; do
  case "$key" in
    MODULE)
      current_id="$val"
      ;;
    SOURCE|YAML|SCRIPT)
      checked_count=$((checked_count + 1))
      key_lower=$(echo "$key" | tr '[:upper:]' '[:lower:]')
      if [[ ! -f "$PLUGIN_ROOT/$val" ]]; then
        echo "ERROR: [$current_id] $key_lower missing: $val"
        error_count=$((error_count + 1))
      fi
      ;;
    ICURSOR|ICLAUDE)
      key_lower=$(echo "$key" | tr '[:upper:]' '[:lower:]')
      if [[ ! -f "$PLUGIN_ROOT/$val" ]]; then
        echo "DRIFT: [$current_id] $key_lower not installed: $val"
        drift_count=$((drift_count + 1))
      fi
      ;;
  esac
done < "$TMPFILE"

# Validate core/scripts/_index.yaml
if [[ -f "$SCRIPTS_INDEX" ]]; then
  SCRIPTS_TMPFILE=$(mktemp)
  trap 'rm -f "$SCRIPTS_TMPFILE"' EXIT

  awk '
    /^  - id:/ {
      if (id != "") flush()
      id = $NF; file = ""
    }
    /^    file:/ { file = $NF }
    END { if (id != "") flush() }

    function flush() {
      print "SCRIPT\t" id "\t" file
    }
  ' "$SCRIPTS_INDEX" > "$SCRIPTS_TMPFILE"

  while IFS=$'\t' read -r key id file; do
    if [[ "$key" == "SCRIPT" ]]; then
      checked_count=$((checked_count + 1))
      script_path="$PLUGIN_ROOT/core/scripts/$file"
      if [[ ! -f "$script_path" ]]; then
        echo "ERROR: [script:$id] file missing: $file"
        error_count=$((error_count + 1))
      fi
    fi
  done < "$SCRIPTS_TMPFILE"
fi

echo ""
echo "METRICS"
echo "  checked: $checked_count"
echo "  errors:  $error_count"
echo "  drift:   $drift_count"

if [[ $error_count -gt 0 ]]; then
  echo "STATUS: ERRORS=$error_count"
  exit 1
else
  echo "STATUS: OK"
  exit 0
fi
