#!/usr/bin/env bash
set -euo pipefail

# Hook 1: session-start.sh (SessionStart)
# Initialize session context — detect IDE, load manifests, determine task type,
# report system readiness.

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# Read JSON input from stdin (SessionStart provides session metadata)
HOOK_INPUT=$(cat)
HOOK_MODEL=$(echo "$HOOK_INPUT" | jq -r '.model // "unknown"' 2>/dev/null || echo "unknown")

# Self-healing: ensure cache symlinks point to source
# If plugin was reinstalled from marketplace, cache is a copy not a symlink.
# Re-create symlinks to live source so edits are immediately reflected.
CONTEXT_FORGE_SOURCE="$(cd "$SCRIPT_DIR/.." && pwd)"
# Read the version from the manifest — a hardcoded one silently stops self-healing
# the cache the moment the plugin version is bumped.
CF_VERSION="$(jq -r '.version // empty' "$CONTEXT_FORGE_SOURCE/.claude-plugin/plugin.json" 2>/dev/null || true)"
[ -z "$CF_VERSION" ] && CF_VERSION="1.1.0"
CF_CACHE="$HOME/.claude/plugins/cache/local/context-forge/$CF_VERSION"

if [ -d "$CONTEXT_FORGE_SOURCE" ] && [ ! -L "$CF_CACHE" ]; then
  rm -rf "$CF_CACHE"
  mkdir -p "$(dirname "$CF_CACHE")"
  ln -s "$CONTEXT_FORGE_SOURCE" "$CF_CACHE"
fi

# Detect IDE_DIR (.claude or .cursor)
if [ -d "${PWD}/.claude" ]; then
  IDE_DIR=".claude"
elif [ -d "${PWD}/.cursor" ]; then
  IDE_DIR=".cursor"
else
  IDE_DIR=".claude"  # fallback
fi

# Detect task type from branch name
detect_task_type() {
  local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

  if [[ "$branch" =~ ^fix/ ]]; then
    echo "bugfix"
  elif [[ "$branch" =~ ^feat/ ]]; then
    echo "new_feature"
  elif [[ "$branch" =~ ^refactor/ ]]; then
    echo "refactor"
  elif [[ "$branch" =~ ^spike/ ]] || [[ "$branch" =~ ^research/ ]]; then
    echo "spike"
  elif [[ "$branch" =~ ^ipa-[0-9]+ ]]; then
    # Jira ticket branches (ipa-NNN-description) — unknown task type
    # Ticket type not determinable from prefix alone; downstream code uses heuristic
    echo "unknown"
  else
    echo "unknown"
  fi
}

# Check manifest freshness for a repo
check_manifest_freshness() {
  local repo_name="$1"
  local manifest_path="${IDE_DIR}/shadow/${repo_name}/_manifest.lightweight.yaml"

  if [ ! -f "$manifest_path" ]; then
    echo "✗ MISSING"
    return 1
  fi

  local generated=$(grep "^  generated:" "$manifest_path" | head -1 | awk '{print $2}' | tr -d '"')
  local generated_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$generated" "+%s" 2>/dev/null || echo "0")
  local now_epoch=$(date +%s)
  local age_seconds=$((now_epoch - generated_epoch))
  local age_hours=$((age_seconds / 3600))
  local age_days=$((age_hours / 24))

  local symbols=$(grep "^  total_symbols:" "$manifest_path" | awk '{print $2}')

  if [ "$age_days" -lt 1 ]; then
    echo "✓ FRESH (${symbols} symbols, ${age_hours}h old)"
    return 0
  elif [ "$age_days" -lt 7 ]; then
    echo "⚠️  STALE (${symbols} symbols, ${age_days}d old)"
    return 1
  else
    echo "✗ BROKEN (${symbols} symbols, ${age_days}d old)"
    return 2
  fi
}

# Detect Superpowers
check_superpowers() {
  if [ -d ~/.claude/plugins/cache/claude-plugins-official/superpowers ] || rg -q "superpowers" ~/.claude/plugins/installed_plugins.json 2>/dev/null; then
    echo "✓ detected"
    return 0
  else
    echo "✗ not found"
    return 1
  fi
}

# Check for code-review-graph MCP
check_code_review_graph() {
  if [ -f ".mcp.json" ] && rg -q "code-review-graph" .mcp.json; then
    echo "✓ configured"
    return 0
  else
    echo "✗ not configured (rg fallback active)"
    return 1
  fi
}

# Check global ~/.claude.json mcpServers for a given server key (rule 015-cf-mcp-tools)
check_mcp_server() {
  local key="$1"
  if [ -f "$HOME/.claude.json" ] && rg -q "\"$key\":" "$HOME/.claude.json" 2>/dev/null; then
    echo "✓"
  else
    echo "✗"
  fi
}

# knowledge is the only local, stateful MCP (ai_knowledge backend under DevHub,
# :3711) — it exposes a real /health endpoint, so check it LIVE, not just for
# config presence. If DevHub is down every mcp__knowledge__* call fails silently.
check_knowledge_live() {
  local url health
  url=$(python3 -c "import json,sys;print(json.load(open('$HOME/.claude.json')).get('mcpServers',{}).get('knowledge',{}).get('url',''))" 2>/dev/null || echo "")
  if [ -z "$url" ]; then
    echo "✗ not configured"
    return
  fi
  health="${url%/mcp}/health"
  if curl -sf -m 2 "$health" >/dev/null 2>&1; then
    echo "✓ live (:3711)"
  else
    echo "⚠ configured but DOWN — start ai-knowledge in DevHub (http://localhost:8080)"
  fi
}

get_capacity_status() {
  local model="$1"
  # Effective limit: 65% of nominal per rule 010
  local effective_k
  case "$model" in
    *fable-5*|*sonnet-4-6*|*opus-4-8*|*opus-4-7*|*opus-4-6*) effective_k=650 ;;  # 1M * 0.65
    *) effective_k=130 ;;  # 200k * 0.65
  esac

  # Proxy: count run-log entries to estimate session token usage
  local date_str
  date_str=$(date +%Y-%m-%d)
  local pwd_hash_val
  pwd_hash_val=$(repo_root_hash)
  local log_file=~/worklogs/runs/${date_str}-${pwd_hash_val}.yaml
  local cmd_count=0
  if [ -f "$log_file" ]; then
    cmd_count=$(rg -c "^- ts:" "$log_file" 2>/dev/null || echo "0")
  fi

  # Each command turn ≈ 500 tokens (conservative)
  local est_used_k=$(( cmd_count * 500 / 1000 ))
  local pct=0
  if [ "$effective_k" -gt 0 ]; then
    pct=$(( est_used_k * 100 / effective_k ))
  fi
  [ "$pct" -lt 0 ] && pct=0
  [ "$pct" -gt 100 ] && pct=100

  local status
  if [ "$pct" -lt 60 ]; then
    status="NORMAL"
  elif [ "$pct" -lt 70 ]; then
    status="WARNING"
  elif [ "$pct" -lt 80 ]; then
    status="PRESSURE"
  else
    status="CRITICAL"
  fi

  echo "${pct}% of ${effective_k}k effective | status: ${status}"
}

# Get model info from session JSON (injected via stdin at startup)
get_model_info() {
  local model="$HOOK_MODEL"
  case "$model" in
    *fable-5*|*opus-4-8*|*opus-4-7*|*opus*1m*|*opus-4-6*) echo "$model (1M nominal, ~650k effective)" ;;
    *sonnet*1m*|*sonnet-4-6*) echo "$model (1M nominal, ~650k effective)" ;;
    *sonnet*) echo "$model (~200k effective)" ;;
    *haiku*) echo "$model (~200k effective)" ;;
    *) echo "$model" ;;
  esac
}

# Main execution
TASK_TYPE=$(detect_task_type)
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Detect active ticket — branch name is primary source, INDEX.yaml is fallback
ACTIVE_TICKET=""
BRANCH_TICKET=$(echo "$BRANCH" | grep -oE '(CRISP|IC|IMM)-[0-9]+' | head -1 || true)
if [ -n "$BRANCH_TICKET" ]; then
  ACTIVE_TICKET="$BRANCH_TICKET"
elif [ -f ~/worklogs/INDEX.yaml ]; then
  ACTIVE_TICKET=$( (rg "^  - key:" ~/worklogs/INDEX.yaml 2>/dev/null || true) | head -1 | awk '{print $3}')
fi

# Resolve plugin root — CLAUDE_PLUGIN_ROOT may be unset outside plugin context
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ] || [ ! -d "$PLUGIN_ROOT" ]; then
  # Fallback: derive from this script's location
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Count repo entries in config/manifest-repos.json
REPOS_JSON="${PLUGIN_ROOT}/config/manifest-repos.json"
REPO_COUNT=$(rg -c "\"name\":" "$REPOS_JSON" 2>/dev/null || echo 0)

# Fallback: detect repos from existing shadow manifests in IDE_DIR
SHADOW_REPOS=""
if [ "$REPO_COUNT" -eq 0 ] && [ -d "${IDE_DIR}/shadow" ]; then
  SHADOW_REPOS=$(ls "${IDE_DIR}/shadow/" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
fi

# Check for script index in core/scripts/
if [ -f "${PLUGIN_ROOT}/core/scripts/_index.yaml" ]; then
  SCRIPT_COUNT=$(rg -c "^  - id:" "${PLUGIN_ROOT}/core/scripts/_index.yaml" 2>/dev/null || echo 0)
else
  SCRIPT_COUNT="0"
fi

# Check if rg is available
RG_STATUS="✓"
if ! command -v rg &> /dev/null; then
  RG_STATUS="✗"
fi

# Check if grep is available (should warn it's BANNED)
GREP_STATUS="✓ BANNED"

# Emit status block
cat << 'EOF'
════════════════════════════════════════════════════════════════
CONTEXTFORGE STATUS (SessionStart)
════════════════════════════════════════════════════════════════
EOF

if [ -n "$ACTIVE_TICKET" ]; then
  if [ -f ~/worklogs/tickets/"${ACTIVE_TICKET}".yaml ]; then
    WORKLOG_ENTRIES=$(rg -c "^- ts:" ~/worklogs/tickets/"${ACTIVE_TICKET}".yaml 2>/dev/null || echo 0)
  else
    WORKLOG_ENTRIES="0"
  fi
  echo ""
  echo "📋 ACTIVE TICKET: $ACTIVE_TICKET"
  echo "   Worklog: ~/worklogs/tickets/${ACTIVE_TICKET}.yaml ($WORKLOG_ENTRIES entries)"
fi

# Cross-session recall: show 3 most recent learnings if available
LEARNINGS_INDEX=~/worklogs/learnings/INDEX.yaml
if [ -f "$LEARNINGS_INDEX" ]; then
  RECENT_LEARNINGS=$( (rg "^  - " "$LEARNINGS_INDEX" 2>/dev/null || true) | tail -3 | sed 's/^/    /')
  if [ -n "$RECENT_LEARNINGS" ]; then
    echo ""
    echo "📚 RECENT LEARNINGS (last 3):"
    echo "$RECENT_LEARNINGS"
  fi
fi

echo ""
echo "🎯 TASK CONTEXT:"
echo "  task_type: $TASK_TYPE"
echo "  branch: $BRANCH"

case "$TASK_TYPE" in
  bugfix) echo "  rule_budget: ~3k tokens (bugfix)" ;;
  new_feature) echo "  rule_budget: ~9k tokens (new_feature)" ;;
  refactor) echo "  rule_budget: ~5k tokens (refactor)" ;;
  spike) echo "  rule_budget: ~2k tokens (spike)" ;;
  *) echo "  rule_budget: ~5k tokens (unknown)" ;;
esac

# Between-session event digest: where the last session left off + confidence gate.
if [ -f "${PLUGIN_ROOT}/core/scripts/tools/session-digest.sh" ]; then
  echo ""
  echo "🧾 SESSION DIGEST:"
  # `|| true`: under the hook's `set -euo pipefail`, a non-zero digest must not
  # abort the rest of SessionStart (never break session startup).
  { bash "${PLUGIN_ROOT}/core/scripts/tools/session-digest.sh" 2>/dev/null | sed 's/^/  /'; } || true
fi

echo ""
echo "📦 MANIFESTS:"
if [ "$REPO_COUNT" -gt 0 ]; then
  echo "  $REPO_COUNT repo(s) configured:"
  # Check freshness for each configured repo
  while IFS= read -r repo_name; do
    [ -z "$repo_name" ] && continue
    freshness=$(check_manifest_freshness "$repo_name" || true)
    echo "    $repo_name: $freshness"
  done < <(rg "\"name\": \"" "$REPOS_JSON" 2>/dev/null | sed 's/.*"name": "\([^"]*\)".*/\1/' || true)
elif [ -n "$SHADOW_REPOS" ]; then
  echo "  (manifest-repos.json empty — shadow manifests found: $SHADOW_REPOS)"
  # Check freshness for each shadow manifest
  for repo_name in $SHADOW_REPOS; do
    [ -z "$repo_name" ] && continue
    freshness=$(check_manifest_freshness "$repo_name" || true)
    echo "    $repo_name: $freshness"
  done
else
  echo "  (no repos configured — run /refresh-manifest to generate)"
fi

echo ""
echo "🔍 SEARCH: rg available $RG_STATUS | grep $GREP_STATUS"

echo ""
CAPACITY_STATUS=$(get_capacity_status "$HOOK_MODEL")
echo "📊 CAPACITY:"
echo "  estimated: $CAPACITY_STATUS"
echo "  model: $(get_model_info)"
echo "  threshold: WARNING at 60% | PRESSURE at 70% | CRITICAL at 80%"

echo ""
echo "🤖 AGENTS:"
echo "  cf-scribe: ready (haiku)"
echo "  tier3_active: 0/2"

echo ""
echo "🧭 ROUTING:"
echo "  enforce-tier-routing.sh: ready"
echo "  route-to-tier.sh: indexed"

echo ""
echo "⚡ TIERS:"
echo "  tier0: rg, diff, wc, git, shadow-lookup.sh"
echo "  tier1: $SCRIPT_COUNT scripts indexed"
echo "  tier2: Task(model: \"haiku\") — cf-scribe"
echo "  tier3: Task(model: \"sonnet\") — max 2 concurrent"

echo ""
echo "🔌 INTEGRATIONS:"
echo "  superpowers: $(check_superpowers)"
echo "  code-review-graph: $(check_code_review_graph)"

echo ""
echo "🌐 MCP (see rule 015-cf-mcp-tools):"
echo "  playwright $(check_mcp_server playwright) | chrome-devtools $(check_mcp_server chrome-devtools) | firecrawl-mcp $(check_mcp_server firecrawl-mcp) | glif $(check_mcp_server glif)"
echo "  knowledge: $(check_knowledge_live)  [local ai_knowledge base, consumed via mcp__knowledge__*]"

echo ""
echo "🔁 SELF-EVOLVE:"
EVOLVE_SIGNAL=$(bash "${PLUGIN_ROOT}/core/scripts/tools/evolve-signal.sh" 2>/dev/null || echo "SIGNAL 0 NO-SIGNAL")
EVOLVE_COUNT=$(echo "$EVOLVE_SIGNAL" | awk '{print $2}')
EVOLVE_STATE=$(echo "$EVOLVE_SIGNAL" | awk '{print $3}')
if [ "$EVOLVE_STATE" = "READY" ]; then
  echo "  SELF-EVOLVE: ${EVOLVE_COUNT} new signals — run /evolve"
else
  echo "  SELF-EVOLVE: ${EVOLVE_COUNT} new signals (below threshold)"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
