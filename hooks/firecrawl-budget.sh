#!/usr/bin/env bash
# firecrawl-budget.sh (PreToolUse — matcher mcp__firecrawl.*)
# The free Firecrawl plan is 1000 credits/month, no pay-as-you-go: at zero every call
# returns 402 until the month rolls over. Cheap calls pass silently; calls whose cost
# scales with pages, minutes or results get "ask" — which forces a permission prompt
# even in auto mode (code.claude.com/docs/en/hooks, PreToolUse decision control).
# Prices: docs.firecrawl.dev/billing, read 2026-10-15.
set -uo pipefail   # never `-e`; unparsable input asks rather than passing silently

python3 -c '
import json, sys
ASK = lambda why: print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Firecrawl credits (1000/month): %s. Try WebFetch/WebSearch first." % why}}))
# Free or flat 1-credit calls. Anything not listed (research_*, parse, future tools) asks:
# an unknown price is not a zero price.
FREE = {"firecrawl_map", "firecrawl_credit_usage", "firecrawl_check_crawl_status",
        "firecrawl_agent_status", "firecrawl_interact_stop", "firecrawl_find_tools",
        "firecrawl_feedback", "firecrawl_search_feedback", "firecrawl_monitor_list",
        "firecrawl_monitor_get", "firecrawl_monitor_checks", "firecrawl_monitor_check",
        "firecrawl_monitor_delete"}
SEARCH = {"firecrawl_search", "firecrawl_developer_search", "firecrawl_gov_search"}
PAID_FORMATS = {"json", "query", "summary", "audio", "changeTracking", "branding"}
try:
    d = json.loads(sys.stdin.read())
    tool = d.get("tool_name", "").split("__")[-1]
    a = d.get("tool_input") or {}
    if tool in FREE:
        sys.exit(0)
    if tool in SEARCH:
        if a.get("scrapeOptions"):
            ASK("search + scrapeOptions bills every result page on top of the search; search alone, then scrape the 1-2 best")
        elif float(a.get("limit") or 5) > 5:
            ASK("limit=%s: 2 credits per 10 results; 5 is the default budget" % a.get("limit"))
        sys.exit(0)
    if tool == "firecrawl_scrape":
        fmts = {f if isinstance(f, str) else f["type"] for f in (a.get("formats") or [])}
        extra = sorted(fmts & PAID_FORMATS) + [k for k in ("lockdown", "redactPII", "actions", "alexandria") if a.get(k)]
        if extra:
            ASK("scrape add-ons %s cost extra per page (+4 each; actions/alexandria undocumented); markdown is 1" % extra)
        sys.exit(0)
    ASK("%s bills per page/minute/run or has no documented price (crawl 1/page, interact 2-7/min, agent dynamic after 5 free runs/day)" % tool)
except SystemExit:
    raise
except Exception as e:
    ASK("could not parse the call (%s) — confirm the cost by hand" % type(e).__name__)
' || echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"firecrawl-budget guard could not run (python3?) — confirm the credit cost by hand"}}'
exit 0
