#!/usr/bin/env bash
set -euo pipefail

# skill-usage.sh — count real ContextForge skill invocations in Claude Code transcripts.
#
# Three call shapes are counted separately, because they answer different questions:
#   skill_tool  — the model invoked the skill itself   ("skill":"context-forge:<id>")
#   slash       — the user typed it                    (<command-name>/context-forge:<id>)
#   agent       — a sub-agent was spawned              ("subagent_type":"context-forge:<id>")
#   script      — the Tier 0/1 script was run via Bash  ("command":"... core/scripts/tools/<id>.sh")
#
# The `script` column exists because the first three miss the path the RULES prescribe.
# Rule 002 and rule 003 route discovery work to a script, not to a skill: the cheapest
# correct tier for `shadow-lookup` is `bash core/scripts/tools/shadow-lookup.sh`, which
# emits no Skill tool call, no slash command and no sub-agent. Counting only those three
# and concluding "the discovery layer is unused" measures the instrument, not the layer
# (H6, core/benchmarks/HYPOTHESES.md). 10 of 22 ids have a same-named script, and they are
# exactly the discovery ones. KNOWN LIMIT: this matches the script path inside a
# `"command"` field, so a Bash call that merely greps for the filename counts as a use;
# it over-counts rather than under-counts, which is the safe direction for a claim of ZERO.
#
# RETENTION CEILING: Claude Code deletes transcripts after `cleanupPeriodDays`
# (default 30, verified in the 2.1.261 binary). This scan therefore reports a
# rolling ~30-day window, never full project history. For history past that
# window an append-only hook log is the only source.
#
# Output: TSV `skill<TAB>skill_tool<TAB>slash<TAB>agent<TAB>script<TAB>total<TAB>last_used`
# Usage: skill-usage.sh [--plugin-root <path>] [--projects <dir>] [--summary]
#
# --summary prints two whole-workflow ratios instead of the per-skill table (targets set 2026-10-15):
#   coverage      sessions with >=1 Skill call / sessions with any tool call   (target >= 50%)
#   raw-research  WebSearch/WebFetch/firecrawl_search calls in sessions with no web-research
#                 skill call / all such calls                                    (target <= 30%)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PROJECTS="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
SUMMARY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-root) PLUGIN_ROOT="$2"; shift 2 ;;
    --projects) PROJECTS="$2"; shift 2 ;;
    --summary) SUMMARY=1; shift ;;
    --help) echo "Usage: skill-usage.sh [--plugin-root <path>] [--projects <dir>] [--summary]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

INDEX="$PLUGIN_ROOT/core/_index.yaml"
[[ -f "$INDEX" ]] || { echo "Missing index: $INDEX" >&2; exit 1; }
[[ -d "$PROJECTS" ]] || { echo "Missing transcripts dir: $PROJECTS" >&2; exit 1; }

if [[ "$SUMMARY" == 1 ]]; then
  python3 - "$PROJECTS" <<'EOF'
import glob, json, os, sys
WEB = {"WebSearch", "WebFetch", "mcp__firecrawl-mcp__firecrawl_search"}
sessions = with_skill = web_total = web_raw = 0
for f in glob.glob(os.path.join(sys.argv[1], "*", "*.jsonl")):
    tools = skills = 0; web = 0; researched = False
    for line in open(f, errors="ignore"):
        try:
            content = (json.loads(line).get("message") or {}).get("content")
        except (ValueError, AttributeError):
            continue
        if not isinstance(content, list):
            continue
        for b in content:
            if not isinstance(b, dict) or b.get("type") != "tool_use":
                continue
            tools += 1
            name = b.get("name", "")
            if name == "Skill":
                skills += 1
                if str((b.get("input") or {}).get("skill", "")).endswith("web-research"):
                    researched = True
            elif name in WEB:
                web += 1
    if not tools:
        continue
    sessions += 1; with_skill += skills > 0
    web_total += web; web_raw += 0 if researched else web
pct = lambda a, b: f"{100 * a // b}%" if b else "n/a"
print("metric\tvalue\tdetail")
print(f"coverage\t{pct(with_skill, sessions)}\t{with_skill}/{sessions} sessions with a Skill call")
print(f"raw-research\t{pct(web_raw, web_total)}\t{web_raw}/{web_total} web calls in sessions with no web-research call")
EOF
  exit 0
fi

# Every id whose entry declares `type: skill` or `type: agent`.
ids="$(awk '/^[[:space:]]*- id:/ {id=$3} /^[[:space:]]*type:[[:space:]]*(skill|agent)/ && id {print id; id=""}' "$INDEX")"

matches="$(rg -o --with-filename --no-line-number \
  -e '"skill":"(context-forge:)?[a-z0-9-]+"' \
  -e '<command-name>/(context-forge:)?[a-z0-9-]+</command-name>' \
  -e '"subagent_type":"(context-forge:)?[a-z0-9-]+"' \
  -e '"command":"[^"]*core/scripts/tools/[a-z0-9-]+\.sh' \
  "$PROJECTS" -g '*.jsonl' 2>/dev/null || true)"

printf 'skill\tskill_tool\tslash\tagent\tscript\ttotal\tlast_used\n'

printf '%s\n' "$ids" | while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  hits="$(printf '%s\n' "$matches" | rg -F "$id" || true)"
  st=0; sl=0; ag=0; sc=0; last='-'
  if [[ -n "$hits" ]]; then
    st=$(printf '%s\n' "$hits" | rg -c "\"skill\":\"(context-forge:)?${id}\"" || true)
    sl=$(printf '%s\n' "$hits" | rg -c "<command-name>/(context-forge:)?${id}</command-name>" || true)
    ag=$(printf '%s\n' "$hits" | rg -c "\"subagent_type\":\"(context-forge:)?${id}\"" || true)
    sc=$(printf '%s\n' "$hits" | rg -c "core/scripts/tools/${id}\.sh" || true)
    # newest transcript that mentions this id, as YYYY-MM-DD
    newest=$(printf '%s\n' "$hits" | sed 's/\.jsonl:.*/.jsonl/' | sort -u \
      | while IFS= read -r f; do
          [[ -f "$f" ]] || continue
          # BSD stat first, GNU second: `stat -f` on GNU prints to stdout AND exits non-zero,
          # so the chain must not be trusted on exit code alone (rule 004).
          stat -f '%m %N' "$f" 2>/dev/null || stat -c '%Y %n' "$f" 2>/dev/null || true
        done | sort -rn | head -1 | cut -d' ' -f1)
    [[ -n "${newest:-}" ]] && last=$(date -r "$newest" '+%Y-%m-%d')
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "${st:-0}" "${sl:-0}" "${ag:-0}" "${sc:-0}" "$(( ${st:-0} + ${sl:-0} + ${ag:-0} + ${sc:-0} ))" "$last"
done | sort -t"$(printf '\t')" -k6,6nr
