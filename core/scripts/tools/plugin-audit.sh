#!/usr/bin/env bash
# plugin-audit.sh — Repeatable audit gate for ContextForge changes.
#
# Usage:
#   bash core/scripts/tools/plugin-audit.sh [--plugin-root <path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-root) PLUGIN_ROOT="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: plugin-audit.sh [--plugin-root <path>]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

PLUGIN_ROOT="$(cd "$PLUGIN_ROOT" && pwd)"
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/plugin-audit.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

failures=0

first_output_line() {
  local file="$1"
  awk 'NF { print; exit }' "$file"
}

first_matching_line() {
  local file="$1"
  local pattern="$2"
  awk -v pattern="$pattern" '$0 ~ pattern { print; exit }' "$file"
}

first_failure_line() {
  local file="$1"
  awk '
    /FAIL|AssertionError|Hook exited|Error:|ERROR:/ { print; found=1; exit }
    NF && fallback == "" { fallback=$0 }
    END { if (!found && fallback != "") print fallback }
  ' "$file"
}

print_result() {
  local name="$1"
  local status="$2"
  local detail="${3:-}"

  if [[ -n "$detail" ]]; then
    echo "- $name: $status ($detail)"
  else
    echo "- $name: $status"
  fi
}

run_step() {
  local name="$1"
  local mode="$2"
  shift 2

  local output="$TMPDIR/$name.log"
  local detail=""

  if (cd "$PLUGIN_ROOT" && "$@") > "$output" 2>&1; then
    case "$mode" in
      parity)
        if awk '/DRIFT:|ORPHAN:|NOT_INSTALLED:/ { found=1 } END { exit found ? 0 : 1 }' "$output"; then
          failures=$((failures + 1))
          detail="$(first_matching_line "$output" "DRIFT:|ORPHAN:|NOT_INSTALLED:")"
          print_result "$name" "FAIL" "${detail:-parity drift detected}"
        else
          print_result "$name" "PASS"
        fi
        ;;
      fail-token)
        if awk '/FAIL/ { found=1 } END { exit found ? 0 : 1 }' "$output"; then
          failures=$((failures + 1))
          detail="$(first_matching_line "$output" "FAIL")"
          print_result "$name" "FAIL" "${detail:-failure marker detected}"
        else
          print_result "$name" "PASS"
        fi
        ;;
      *)
        print_result "$name" "PASS"
        ;;
    esac
  else
    failures=$((failures + 1))
    detail="$(first_failure_line "$output")"
    print_result "$name" "FAIL" "${detail:-command exited non-zero}"
  fi
}

echo "[PLUGIN AUDIT]"
echo "- plugin-root: $PLUGIN_ROOT"

run_step "validate-index" "exit-code" npm run validate-index
run_step "check-parity" "parity" bash core/scripts/tools/check-parity.sh --plugin-root .
run_step "audit-runtime-artifacts" "exit-code" bash core/scripts/tools/audit-runtime-artifacts.sh --plugin-root .
run_step "audit-doc-claims" "exit-code" bash core/scripts/tools/audit-doc-claims.sh --plugin-root .
run_step "audit-plugin-surface" "exit-code" bash core/scripts/tools/audit-plugin-surface.sh --plugin-root .
run_step "audit-rules" "fail-token" bash core/scripts/tools/audit-rules.sh
run_step "benchmark-tokens" "exit-code" bash core/scripts/tools/benchmark-tokens.sh --compare core/benchmarks/baseline-2026-06-19.tsv
run_step "npm-test" "exit-code" npm test

if [[ "$failures" -eq 0 ]]; then
  echo "- final: PASS"
  echo "[END PLUGIN AUDIT]"
  exit 0
fi

echo "- final: FAIL ($failures failing gate(s))"
echo "[END PLUGIN AUDIT]"
exit 1
