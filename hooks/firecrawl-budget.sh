#!/usr/bin/env bash
# firecrawl-budget.sh (PreToolUse — matcher mcp__firecrawl.*)
# The free Firecrawl plan is 1000 credits/month, no pay-as-you-go: at zero every call
# returns 402 until the month rolls over. Calls run without a prompt; the guard instead
#   - estimates each call's credit cost and appends it to firecrawl-usage.tsv,
#   - tracks remaining credits from GET /v2/team/credit-usage (re-read 5 min after the
#     last API fetch, decremented by each estimate in between),
#   - denies an uncapped crawl, malformed input, or a call that would push remaining
#     below the floor; asks when remaining credits are unknown (no key, API down).
# Every allowed call carries one line of additionalContext: estimate, remaining, calls today.
# Unpriced tools (agent, interact, research_*) are booked at 10 — the floor is soft for them.
# Prices: docs.firecrawl.dev/billing, read 2026-10-15. Endpoint shape verified 2026-10-21.
# Env: FIRECRAWL_API_KEY (else read from ~/.claude.json mcpServers), CF_FIRECRAWL_DIR
# (state + log, default ~/worklogs/logs), CF_FIRECRAWL_FLOOR (default 200).
set -uo pipefail   # never `-e`: a broken guard must not silently block or pass

python3 -c '
import fcntl, json, math, os, sys, time, urllib.request
DIR = os.path.expanduser(os.environ.get("CF_FIRECRAWL_DIR", "~/worklogs/logs"))
STATE, LOG = os.path.join(DIR, "firecrawl-credits.json"), os.path.join(DIR, "firecrawl-usage.tsv")
TTL, UNKNOWN_EST = 300, 10

def out(decision, msg):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
        "permissionDecision": decision, "permissionDecisionReason": msg, "additionalContext": msg}}))

FREE = {"firecrawl_map", "firecrawl_credit_usage", "firecrawl_check_crawl_status",
        "firecrawl_agent_status", "firecrawl_interact_stop", "firecrawl_find_tools",
        "firecrawl_feedback", "firecrawl_search_feedback", "firecrawl_monitor_list",
        "firecrawl_monitor_get", "firecrawl_monitor_checks", "firecrawl_monitor_check",
        "firecrawl_monitor_delete"}
SEARCH = {"firecrawl_search", "firecrawl_developer_search", "firecrawl_gov_search"}
PAID_FORMATS = {"json", "query", "summary", "audio", "changeTracking", "branding"}

def count(a, key, default):
    """A positive whole count; a negative, zero or fractional value would under-bill."""
    if a.get(key) is None:
        if default is None:
            raise ValueError("%s is required (an uncapped call bills every page it finds)" % key)
        return default
    v = float(a[key])
    if not (v >= 1 and v == int(v)):
        raise ValueError("%s=%r is not a positive whole number" % (key, a[key]))
    return int(v)

def page_cost(o):
    # 1 per markdown page, +4 per paid format; unpriced add-ons count as unknown (None).
    fmts = o.get("formats") or []
    if not isinstance(fmts, list):
        raise ValueError("formats must be a list")
    names = {f if isinstance(f, str) else f["type"] for f in fmts}
    if any(o.get(k) for k in ("lockdown", "redactPII", "actions", "alexandria")):
        return None
    return 1 + 4 * len(names & PAID_FORMATS)

def estimate(tool, a):
    """Credits, or None when the price is undocumented. Raises ValueError to deny."""
    if tool in SEARCH:
        n = count(a, "limit", 5)
        cost = 2 * math.ceil(n / 10)
        if a.get("scrapeOptions"):
            pc = page_cost(a["scrapeOptions"])
            return None if pc is None else cost + n * pc
        return cost
    if tool == "firecrawl_scrape":
        return page_cost(a)
    if tool == "firecrawl_crawl":
        return count(a, "limit", None) * (page_cost(a.get("scrapeOptions") or {}) or UNKNOWN_EST)
    return None   # agent, interact, research_*, parse, monitor writes: unpriced

def api_key():
    k = os.environ.get("FIRECRAWL_API_KEY")
    if k:
        return k
    def find(o):
        if isinstance(o, dict):
            srv = o.get("firecrawl-mcp")
            env = srv.get("env") if isinstance(srv, dict) else None
            if isinstance(env, dict) and env.get("FIRECRAWL_API_KEY"):
                return env["FIRECRAWL_API_KEY"]
            for v in o.values():
                r = find(v)
                if r:
                    return r
    try:
        return find(json.load(open(os.path.expanduser("~/.claude.json"))))
    except Exception:
        return None

def load():
    try:
        s = json.load(open(STATE))
        return s if isinstance(s.get("remaining"), int) and isinstance(s.get("fetched"), (int, float)) else None
    except Exception:
        return None

def save(rem, plan, fetched):
    # Atomic replace: a reader never sees a half-written file.
    tmp = STATE + ".tmp"
    json.dump({"fetched": fetched, "remaining": rem, "plan": plan}, open(tmp, "w"))
    os.replace(tmp, STATE)

def remaining():
    """(remaining, plan, fetched) — local count until TTL after the last API fetch; None if unknown."""
    s, now = load(), time.time()
    if s and 0 <= now - s["fetched"] < TTL:
        return s["remaining"], s.get("plan"), s["fetched"]
    key = api_key()
    if key:
        try:
            req = urllib.request.Request("https://api.firecrawl.dev/v2/team/credit-usage",
                                         headers={"Authorization": "Bearer " + key})
            d = json.load(urllib.request.urlopen(req, timeout=3))["data"]
            return int(d["remainingCredits"]), d["planCredits"], now
        except Exception:
            pass
    return (s["remaining"], s.get("plan"), s["fetched"]) if s else (None, None, None)   # stale beats nothing

def calls_today():
    day = time.strftime("%Y-%m-%d")
    try:
        return sum(1 for l in open(LOG) if l.startswith(day))
    except OSError:
        return 0

try:
    FLOOR = int(os.environ.get("CF_FIRECRAWL_FLOOR", "200"))
    d = json.loads(sys.stdin.read())
    tool = d.get("tool_name", "").split("__")[-1]
    a = d.get("tool_input") or {}
    if not tool.startswith("firecrawl_") or not isinstance(a, dict):
        out("ask", "firecrawl-budget: unrecognised call %r — confirm the cost by hand" % tool); sys.exit(0)
    if tool in FREE:
        sys.exit(0)
    try:
        est = estimate(tool, a)
    except (ValueError, TypeError, KeyError) as e:
        out("deny", "firecrawl-budget: %s: %s" % (tool, e)); sys.exit(0)
    cost = UNKNOWN_EST if est is None else est
    os.makedirs(DIR, exist_ok=True)
    # Lock the read-check-write so parallel calls cannot all pass the floor on one value.
    with open(STATE + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        rem, plan, fetched = remaining()
        if rem is None:
            out("ask", "firecrawl-budget: remaining credits unknown (no API key or API unreachable); "
                "%s costs ~%s — confirm by hand" % (tool, cost)); sys.exit(0)
        if rem - cost < FLOOR:
            out("deny", "firecrawl-budget: %s needs ~%s credits, %s left, floor %s. Use WebFetch/WebSearch; "
                "raise CF_FIRECRAWL_FLOOR only if the user says so." % (tool, cost, rem, FLOOR)); sys.exit(0)
        left = rem - cost
        save(left, plan, fetched)   # keeps the API fetch time, so the TTL still expires
        with open(LOG, "a") as f:
            f.write("%s\t%s\t%s\t%s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S"), tool,
                    "?" if est is None else est, left))
    out("allow", "firecrawl-budget: %s ~%s credits; %s/%s left; %d paid calls today" % (
        tool, "?" if est is None else est, left, plan or "?", calls_today()))
except SystemExit:
    raise
except Exception as e:
    out("ask", "firecrawl-budget: guard failed (%s) — confirm the cost by hand" % type(e).__name__)
' || echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"firecrawl-budget guard could not run (python3?) — confirm the credit cost by hand"}}'
exit 0
