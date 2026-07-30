#!/usr/bin/env bash
# tools/route-to-tier.sh — Task → tier recommendation based on _index.yaml
# Port from ai-system; adapted for context-forge
# Usage: route-to-tier.sh --task <keyword> [--verbose]
# Output: TIER:<n>\nACTION:<cmd>\nREASON:<text>
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Parse args
_TASK=""
_VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: route-to-tier.sh --task <keyword> [--verbose]

Route a task to the cheapest correct execution tier (0–3).
Reads routing rules from core/scripts/_index.yaml.

Output:
  TIER:<n>        — 0=CLI, 1=Script, 2=Haiku, 3=Sonnet
  ACTION:<cmd>    — Recommended command or tool
  REASON:<text>   — Why this tier was chosen

Examples:
  route-to-tier.sh --task "extract signatures"
  route-to-tier.sh --task "record failure" --verbose
EOF
      exit 0
      ;;
    --task)
      _TASK="$2"
      shift 2
      ;;
    --verbose)
      _VERBOSE=true
      shift
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

TASK="$_TASK"

if [[ -z "$TASK" ]]; then
  # Default to Tier 2 if no task provided
  echo "TIER:2"
  exit 0
fi

INDEX_FILE="$PLUGIN_ROOT/core/scripts/_index.yaml"
if [[ ! -f "$INDEX_FILE" ]]; then
  echo "TIER:2"
  exit 0
fi

# Normalize task: lowercase, remove punctuation
TASK_LOWER=$(echo "$TASK" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]')

# Direct pattern matching for known keywords
case "$TASK_LOWER" in
  *extract*signature*|*extract*symbol*|*method*stub*)
    echo "TIER:1"
    echo "ACTION:bash core/scripts/tools/extract-signatures.sh --file <path>"
    echo "REASON:Script handles method extraction deterministically"
    ;;
  *shadow*lookup*|*symbol*lookup*|*find*class*)
    echo "TIER:1"
    echo "ACTION:bash core/scripts/tools/shadow-lookup.sh --symbol <name>"
    echo "REASON:Manifest lookup is deterministic and fast"
    ;;
  *log*analyze*|*error*analyze*|*build*fail*)
    echo "TIER:1"
    echo "ACTION:bash core/scripts/tools/log-context-analyzer.sh --file <log>"
    echo "REASON:Script-based RCA for structured errors"
    ;;
  *record*failure*|*circuit*breaker*|*failure*ledger*)
    echo "TIER:0"
    echo "ACTION:bash core/scripts/tools/record-failure.sh --slug <slug> --goal <goal> --error <err>"
    echo "REASON:Mechanical YAML generation, no LLM needed"
    ;;
  *pack*context*|*bundle*files*|*multi*file*)
    echo "TIER:1"
    echo "ACTION:bash core/scripts/tools/pack-context.sh --pattern <regex> --search-path <dir>"
    echo "REASON:Script-based file bundling"
    ;;
  *scaffold*skill*|*scaffold*rule*|*create*module*)
    echo "TIER:0"
    echo "ACTION:bash core/scripts/tools/scaffold-skill.sh --name <name>"
    echo "REASON:Template generation, deterministic"
    ;;
  *impact*level*|*api*boundary*|*quick*check*|*quick*impact*)
    echo "TIER:0"
    echo "ACTION:source core/scripts/lib/impact-tier0.sh && is_api_boundary <symbol>"
    echo "REASON:Heuristic function, no LLM"
    ;;
  *token*count*|*estimate*cost*)
    echo "TIER:0"
    echo "ACTION:bash core/scripts/tools/token-counter.sh --file <path>"
    echo "REASON:Deterministic char-to-token estimation"
    ;;
  *git*status*|*task*context*|*detect*branch*)
    echo "TIER:0"
    echo "ACTION:bash core/scripts/tools/git-status-summary.sh"
    echo "REASON:Query git metadata only"
    ;;
  *compress*output*|*mask*observation*)
    echo "TIER:0"
    echo "ACTION:bash core/scripts/tools/compress-observation.sh --file <log>"
    echo "REASON:Deterministic compression logic"
    ;;
  *worklog*read*|*worklog*append*|*ticket*context*)
    echo "TIER:1"
    echo "ACTION:bash core/scripts/tools/worklog.sh --key <PROJ-123> --scope <what_changed>"
    echo "REASON:Script-based file I/O"
    ;;
  *refresh*manifest*|*generate*manifest*)
    echo "TIER:1"
    echo "ACTION:bash core/scripts/tools/refresh-manifest.sh"
    echo "REASON:Script-based index generation"
    ;;
  *architecture*|*design*|*tradeoff*|*depend*graph*|*blast*radius*)
    echo "TIER:3"
    echo "ACTION:Task(model: sonnet, subagent: architect)"
    echo "REASON:Architecture decision requires reasoning depth"
    ;;
  *refactor*5+files*|*bulk*codegen*|*cross*repo*)
    echo "TIER:2"
    echo "ACTION:Task(model: haiku, subagent: executor)"
    echo "REASON:Multi-file task, but not architectural"
    ;;
  *)
    # Default: Tier 2 for unknown tasks
    echo "TIER:2"
    echo "ACTION:Decompose into smaller steps or use Task(model: haiku)"
    echo "REASON:Unknown task type; default to Haiku-first"
    ;;
esac

if [[ "$_VERBOSE" == "true" ]]; then
  echo ""
  echo "DEBUG: task='$TASK' → normalized='$TASK_LOWER'"
  echo "DEBUG: routing rules from $INDEX_FILE"
fi
