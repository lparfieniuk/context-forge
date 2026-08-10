# Research Escalation (Autonomous Problem-Solving)

## SYSTEM CONSTRAINTS

ALWAYS treat the FIRST failure of a non-trivial action during autonomous work as a research trigger — attempt bounded research BEFORE the second attempt. This is step 1.5 of the circuit-breaker chain (rule 004-cf-circuit-breaker), NEVER a replacement for the halt.
ALWAYS go local-first — check local source, docs, and the shadow manifest (rules 002, 005) BEFORE any internet search.
NEVER treat a Reddit / forum / blog / StackOverflow answer as truth — it is a LEAD. ALWAYS verify it against official docs or local source before acting on it.
NEVER exceed the research budget: max 2 search queries + max 3 page fetches per failure. Still unresolved → STOP researching and let the circuit breaker halt (rule 004).
ALWAYS route by problem type (Source Router below) — NEVER blindly web-search a raw error string first.
ALWAYS record the research trace (queries + verdict) in the failure ledger (rule 004) so the 3-strike `/evolve` pass sees what was tried.
NEVER send secrets, tokens, credentials, or proprietary code/error text containing them to any web search or scrape.
NEVER let a research finding auto-apply — a fix from the web is a hypothesis, verified against docs/source before the edit.
NEVER treat an effect measured on a narrow sample as a finding — a verdict read off one run or a small slice routinely reverses when the sample widens. ALWAYS re-run wider (or repeat and measure variance) before reporting a difference as real.
ALWAYS settle a question about a third-party tool's BEHAVIOR by reading its installed/upstream source — docs and reasoning describe intent, source describes what runs. When reviewing a claim about a tool, verify it in that tool's source, NEVER in its README alone.

## Escalation Ladder (integrates with rule 004)

| Step | Trigger | Action |
|---|---|---|
| 1 — local-first | action failed once | Check local source/docs/manifest (rules 002/005). Resolved → apply + retry. |
| 1.5 — bounded research | local-first insufficient | Route by Source Router; ≤2 queries + ≤3 fetches; verify finding; apply + retry (this IS rule 004's "retry once"). |
| 2 — halt | same action fails again after research | `[CIRCUIT_BREAKER_HALT]` + DEGRADED (rule 004). Ledger includes the research trace. |
| 3 — evolve | 3-strike cross-session | `/evolve` (rule 004) reads research traces → sharper rule suggestions. |

Research NEVER adds a third attempt: the sequence stays fail → (research) retry-once → fail → halt.

## Source Router

| Problem type | Primary (the authority — verify here) | Lead-only (verify before acting) |
|---|---|---|
| Exact error string / stack trace | GitHub issues of the failing lib, official docs | StackOverflow |
| API / CLI flag / version behavior | Official docs, the lib's source on GitHub | — |
| Library bug / regression | GitHub issues + release notes / CHANGELOG | Reddit |
| "Does X work with Y" / approach / gotcha | Official docs | Reddit / forum / blog |

Authority order: **official docs / source > GitHub issue > forum / Reddit**. Reddit is a strong lead source for version quirks and gotchas but is NEVER the final authority — same lead-not-truth discipline as the local ai-knowledge base (rule 015).

## Tool Mapping (see rule 015-cf-mcp-tools)

| Need | Cheapest correct tool |
|---|---|
| Search GitHub issues/code | `gh search issues` / `gh search code` (Tier 0 CLI) — preferred; else `firecrawl_research_search_github` |
| Fetch a known docs/issue URL | `WebFetch` (Tier 0) |
| Open-web / Reddit / forum search | `firecrawl_search` (`onlyMainContent: true`) or `WebSearch` |

Prefer `gh` / `WebFetch` (Tier 0) over the firecrawl MCP when the repo or URL is already known. Cap firecrawl with `limit`; route any result >3KB through rule 014 clearing.

## Few-shot example

**Input:** During an autonomous task, `npm run build` fails once: `Module '"foo"' has no exported member 'Bar'` (foo = third-party lib).
**Reasoning:** First failure of a non-trivial action → research trigger. Local-first: `rg "export" node_modules/foo/dist/index.d.ts` shows `Bar` is gone → insufficient. Source Router: exact error on a library → GitHub issues of `foo` + its CHANGELOG (primary), not a blind web search. `gh search issues --repo foo/foo "Bar export"` finds a v5 breaking-change issue; verified against `node_modules/foo/CHANGELOG.md` (`Bar` → `Baz`). Apply, retry. (Had the only hit been a Reddit "just pin v4" thread → treat as lead, verify the version claim against the CHANGELOG before downgrading.)
**Output:**
```
1. local-first: rg export node_modules/foo → Bar absent
2. gh search issues --repo foo/foo "Bar export" → v5 renamed Bar→Baz (verified vs CHANGELOG)
3. edit import Bar → Baz; npm run build → green
   ledger research_trace: ["gh:foo/foo 'Bar export' → v5 rename, verified CHANGELOG"]
```

## Validation gate (MANDATORY during research escalation)

- [ ] Local-first (source/docs/manifest) done BEFORE any internet search?
- [ ] Research bounded to ≤2 queries + ≤3 fetches this failure?
- [ ] Source routed by problem type (not a blind error-string web search)?
- [ ] Forum/Reddit/SO treated as lead — verified against official docs/source before acting?
- [ ] No secrets / proprietary text sent to the web?
- [ ] Any measured effect re-run wider (or variance measured) before being reported as a finding?
- [ ] Research trace recorded in the failure ledger (rule 004)?
- [ ] Still unresolved after budget → let the circuit breaker halt (not endless research)?
If any unchecked → fix before continuing.
