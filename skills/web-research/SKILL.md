---
name: web-research
description: Answers one research question from the web with cited sources, routing each sub-question to the cheapest dedicated source (library docs, GitHub, YouTube, papers, open web) instead of raw WebSearch. Use when the user says "zbadaj", "poszukaj", "sprawdź w internecie", "co nowego w", "porównaj", "research", "look up", "compare", "what's new in", or when a task needs facts the repo and the knowledge base do not hold. Do NOT use for a standing weekly scan (that is research-scan), for "which tool/library/MCP exists" before checking our own base (tool-scout first), or for a library API question context7 answers alone.
model: inherit
---

## What This Does

A router, not a crawler. Every question goes through the same steps: local first, then the
single most specific source, then the open web, then (only if asked) a deep multi-source run.
The output is a short cited answer, plus a saved report when the research was non-trivial.

## Step 0 — Local first (rule 016)

1. Repo / installed source / docs for anything about code we run.
2. Tool, library or MCP question → `tool-scout` before the web.

## Step 1 — Route by source (dedicated before generic)

| Question is about | Use | Notes |
|---|---|---|
| A library/framework/SDK API | `mcp__context7__resolve-library-id` → `query-docs` | Fresher than memory |
| GitHub repos, issues, PRs, code | `gh` CLI (Tier 0), else `firecrawl_developer_search` | Never `site:github.com` web search |
| A YouTube video | `youtube-transcript` skill | Never scrape the watch page |
| Papers (arXiv, biomed) | `firecrawl_research_search_papers` / `read_paper` | |
| One known page | `WebFetch`, else `firecrawl_scrape` | |
| Open web | 3+ **differently worded** queries: `WebSearch` (mode standard) or `firecrawl_search` | One query = one blind spot |
| Many sources / dataset / "deep" | `firecrawl_agent` → `firecrawl_agent_status` | Deep mode only, see budget |

Modes: **quick** (default — ≤2 queries, ≤3 fetches, rule 016 budget) · **varied** (user asks to
compare coverage: 3 web + 3 GitHub + 1 developer-search) · **deep** (user says "deep"/"dogłębnie").

## Step 2 — Budget and failures

- Deep mode: run `firecrawl_credit_usage` first; state expected spend (rule 017).
- Firecrawl errors (`Unauthorized`, quota) → fall back to WebSearch/WebFetch and SAY the gap.
- Reddit/forum/X = lead, not truth: confirm against official docs or source before stating it.
- Two identical failures → `[CIRCUIT_BREAKER_HALT]` (rule 004).

## Step 3 — Output

- Answer first (≤5 bullets), every factual bullet carries its source URL.
- Mark each claim `verified` (primary source read) or `lead` (secondary only).
- "Not found" is a valid result — say what was searched.
- Non-trivial research (varied/deep, or >3 sources): save to
  `~/worklogs/research/YYYY/MM/YYYY-MM-DD-<slug>.md` and print the path. NEVER inside a repo.

## Constraints

ALWAYS check the repo and `tool-scout` before the web for anything about code or tools we use.
NEVER state a `lead`-only claim as fact; NEVER exceed the quick-mode budget without the user asking.
NEVER run `firecrawl_agent` or an uncapped crawl without a credit check (rule 017).

## Few-shot

**Input:** "zbadaj co nowego w Angular 21"
**Output:** context7 `/angular/angular` release notes + 2 differently worded WebSearch queries →
5 cited bullets (signals API change, zoneless default, …), each marked `verified`; no file saved (quick mode).
