#!/usr/bin/env bash
# failure-replay.sh — turn a rule-004 failure ledger into a cf-bench regression case.
#
# The bench golden-set philosophy says every production incident should become a
# case, but nothing connected ledgers to the bench, so incidents stayed prose.
# This scaffolds the mechanical half: classification + draft task + fixture stub.
# The judgment half (a real fixture and a real check.sh) stays human — a generated
# check that never ran proves nothing.
#
# Drafts land under tasks/_drafts/, which the matrix glob (tasks/*.task) never
# picks up: an incomplete case costs nothing and cannot silently enter a run.
#
# Usage:
#   bash core/scripts/tools/failure-replay.sh --ledger <path> [--bench-root <path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BENCH_ROOT="${CFBENCH_ROOT:-$HOME/Projects/ai-tools/cf-bench}"
LEDGER=""

# Ledger fields sit one indent level deep; lib/yaml.sh matches top-level keys
# only, so extract locally — with quote stripping.
ledger_field() {
  local key="$1"
  sed -nE "s/^[[:space:]]*${key}:[[:space:]]*\"?(.*)\"?[[:space:]]*\$/\1/p" "$LEDGER" | head -1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ledger) LEDGER="$2"; shift 2 ;;
    --bench-root) BENCH_ROOT="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: failure-replay.sh --ledger <path> [--bench-root <path>]"
      echo "  Classify a rule-004 ledger and scaffold a DRAFT cf-bench regression case."
      echo "  Bench-replayable -> \$BENCH/tasks/_drafts/replay-<slug>.task + fixture stub."
      echo "  Process-only     -> verdict + reason, no artifacts."
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$LEDGER" ]] || { echo "FATAL: ledger not found: $LEDGER" >&2; exit 1; }

GOAL="$(ledger_field goal || true)"
TOOL="$(ledger_field tool || true)"
TRAJECTORY="$(awk '/^error_trajectory:/{f=1;next} /^[a-z_]+:/{f=0} f' "$LEDGER" | head -20)"
REFLECTION="$(ledger_field agent_reflection || true)"

BASENAME="$(basename "$LEDGER" .yaml)"
SLUG="$(printf '%s' "$BASENAME" | sed -E 's/^[0-9a-f]{8}-//')"

echo "=== FAILURE REPLAY ==="
echo "  ledger: $LEDGER"
echo "  slug:   $SLUG"

REPLAYABLE=no
REASON=""
if printf '%s' "$TOOL $GOAL $TRAJECTORY" | rg -qi 'npm|build|test|tsc|vitest|jest|eslint|vite|ng |nx |TS[0-9]{4}|ERR!'; then
  REPLAYABLE=yes
else
  REASON="no build/test/code signal in tool/goal/error_trajectory — the failure is process or policy, not a reproducible code scenario"
fi

if [[ "$REPLAYABLE" != "yes" ]]; then
  echo "- verdict: NOT REPLAYABLE ($REASON)"
  echo "  A ledger that is not a code scenario still belongs in /evolve signal — do not force it into the bench."
  echo "[END FAILURE REPLAY]"
  exit 0
fi

if [[ ! -d "$BENCH_ROOT" ]]; then
  echo "FATAL: bench root not found: $BENCH_ROOT (pass --bench-root)" >&2
  exit 1
fi
if [[ ! -x "$BENCH_ROOT/runner/run-task.sh" ]]; then
  echo "FATAL: $BENCH_ROOT does not look like cf-bench (runner/run-task.sh missing)" >&2
  exit 1
fi

DRAFTS="$BENCH_ROOT/tasks/_drafts"
FIXTURE="$BENCH_ROOT/fixtures/replay-$SLUG"
mkdir -p "$DRAFTS" "$FIXTURE"

TASK_FILE="$DRAFTS/replay-$SLUG.task"
cat > "$TASK_FILE" <<EOF
# DRAFT replay case scaffolded from a rule-004 ledger by failure-replay.sh.
# INERT until moved to tasks/: run-bench globs only tasks/*.task (non-recursive).
# Before promoting:
#   1. Build fixtures/replay-$SLUG/ so the scenario is reproducible offline.
#   2. Write a REAL check.sh (stub below always fails) that passes iff the
#      failure is fixed. Validate: runner/validate-tasks.sh must accept it.
#   3. mv $TASK_FILE $BENCH_ROOT/tasks/
# Ledger context lives in fixtures/replay-$SLUG/LEDGER.md.
TASK_ID="replay-$SLUG"
PROMPT="$GOAL"
FIXTURE="replay-$SLUG"
CONFIG=""
MAX_TURNS="12"
CHECK="check.sh"
EOF

cat > "$FIXTURE/check.sh" <<'EOF'
#!/usr/bin/env bash
# DRAFT stub — ALWAYS FAILS so this case can never pass by accident.
# Replace with a deterministic assertion: exit 0 iff the recorded failure is fixed.
echo "check.sh is a scaffold stub — implement it before promoting the task out of tasks/_drafts/" >&2
exit 3
EOF
chmod +x "$FIXTURE/check.sh"

{
  echo "# Replay context — extracted verbatim from: $LEDGER"
  echo
  echo "## execution_context"
  echo "- goal: ${GOAL:-<unset>}"
  echo "- tool: ${TOOL:-<unset>}"
  echo
  echo "## error_trajectory"
  echo '```'
  [[ -z "$TRAJECTORY" ]] || printf '%s\n' "$TRAJECTORY"
  echo '```'
  echo
  echo "## agent_reflection"
  echo "${REFLECTION:-<unset>}"
  echo
  echo "## Authoring checklist"
  echo "- [ ] Fixture reproduces the pre-fix state deterministically (offline deps)."
  echo "- [ ] check.sh asserts the FIXED behavior, not the absence of one error string."
  echo "- [ ] runner/validate-tasks.sh accepts the task; sanity gate fails pre-run."
} > "$FIXTURE/LEDGER.md"

echo "- verdict: REPLAYABLE"
echo "- draft task:   $TASK_FILE (inert — tasks/_drafts/ is outside the matrix glob)"
echo "- draft fixture: $FIXTURE/ (check.sh is a failing stub by design)"
echo "- next: author fixture + real check.sh, validate-tasks.sh, then mv the task to tasks/"
echo "[END FAILURE REPLAY]"
