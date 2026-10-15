---
name: tool-scout
description: Looks up the user's own ai-knowledge base (400+ saved tools, AI libraries, MCP servers, agent patterns) before anything else. Use when the user asks "jakie narzędzie / biblioteka / MCP do…", "czy jest coś do…", "co mamy w bazie o…", "is there a tool/library/MCP for…", "what do we know about <tool>", or before adding a new dependency or MCP server. Do NOT use for general web research with no tool/library angle (that is web-research) or for API usage of an already-chosen library (context7).
model: inherit
---

## What This Does

Treats `~/Projects/ai_knowledge` as Claude's memory of tools the user already found. The catalog is
built from the entries on disk, so it works even when the knowledge MCP (DevHub backend) is down.

## Steps

1. Refresh if stale (no-op when fresh):
   `bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/knowledge-catalog.sh --if-stale`
2. Search the catalog — TSV `title  tags  source_url  id  summary`, ~400 rows. NEVER read it whole:
   `rg -i '<term1>|<term2>' ~/worklogs/wiki/ai-knowledge/catalog.tsv | cut -c1-200`
   Try 2–3 synonyms (PL + EN: "przeglądarka|browser|playwright").
3. Detail for the best 1–3 hits: `mcp__knowledge__get_entry` (id) when the MCP is up, else
   `rg -l '<id>' ~/Projects/ai_knowledge/entries` and read that file.
4. Verify before recommending: entries are often OCR'd social posts with stale star counts. Check
   the repo/docs (`gh repo view`, context7) — knowledge entries are leads, not truth (rule 015).
5. Nothing relevant → hand off to `web-research`.

## Output

| Tool | Why it fits | Entry id | Verified? |
|---|---|---|---|

Pick one and name the runner-up in a clause (rule 001). Always state the cost: new dependency,
new MCP server (context + process), or paid API.

## Constraints

NEVER read the whole catalog into context — `rg` it. NEVER recommend an entry without checking its
repo/docs. ALWAYS name the cost of adopting the pick.

## Few-shot

**Input:** "jakie mamy MCP do przeglądarki?"
**Output:** `rg -i 'browser|przeglądark|playwright|chrome|puppeteer' catalog.tsv` → 2 hits ("Browser Use",
"Awesome MCP Servers") → table; then note what is already installed (playwright / chrome-devtools
plugins, per-project) — pick: Playwright plugin; runner-up: Browser Use (new dependency, verify repo first).
