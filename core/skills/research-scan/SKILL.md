---
name: research-scan
description: Runs one bounded research pass against a project's scan program, deduplicates every finding against the ai-knowledge base before writing anything, and leaves a delta report plus an alert line when a finding is existential. Use when the user says "run the research scan", "/research-scan", "what changed in the landscape", "weekly scan", or when a scheduled headless run invokes it. Do NOT use for answering a single research question (that is WebSearch plus rule 016), for capturing what THIS session learned (that is session-learnings), or without a scan program file — the program is the input, and a scan without one is an unbounded web crawl.
model: sonnet
---

## What This Does

Executes ONE pass of a project's standing research program and stops. Four things happen
in order, and the order is the whole point:

1. **Scan** the sources the program names, inside the program's search budget.
2. **Deduplicate** every candidate finding against the ai-knowledge base BEFORE it is
   written anywhere. A finding already in the base is dropped, not restated.
3. **Record** what survives — new entries into ai-knowledge with the program's tags.
4. **Report** the delta into `~/worklogs/research/YYYY/MM/YYYY-MM-DD-<project>.md`,
   and raise `/evolve` when a finding concerns this plugin's own rules or skills.

The value is step 2. Stateless deep research restarts from zero every time and hands back
a report that is 80% things you already knew. Deduplicating against a persistent base is
what turns a series of one-off reports into a continuous loop.

## When to Use

**Trigger:**
- `/research-scan` (manual), optionally with a path to the program file
- a scheduled headless run (`claude -p`, launchd/cron)
- the SessionStart reminder when the last scan for this project is over 7 days old

**Skip:**
- no scan program exists for this project — write the program first, do not improvise one
- the last scan for this project ran today; a same-day rescan is defined to produce nothing

## Input: the scan program

The program is a per-project file. Resolution order:

1. the path the user passed
2. `<repo>/research-routine/RESEARCH-ROUTINE.md`
3. `~/worklogs/research/programs/<project>.md`

It defines the sources, the search budget, the report shape, the tags, and the ALERT
condition. Reference implementation: `~/Projects/ai-tools/research-routine/RESEARCH-ROUTINE.md`.
If none of the three exist, STOP and say so — do not substitute your own source list.

## How to Use

1. Resolve and read the program file. Its search budget is a hard ceiling, not a target.
2. Scan the named sources for what is new since the last report. Find the last report:
   `ls ~/worklogs/research/*/*/*-<project>.md 2>/dev/null | tail -1`
3. For EVERY candidate finding, before writing it anywhere:
   `mcp__knowledge__search_knowledge` with the finding's key phrase. Present and unchanged
   → drop it. Present but changed → record only the delta, and reference the existing entry.
4. Write survivors into ai-knowledge with the program's tags. If the base is unreachable or
   read-only, put them under a `## To add to ai-knowledge` heading in the report instead —
   never silently discard them.
5. Write the delta report. Every claim carries a source link, or the literal marker
   `[unverified]`. A claim with neither does not go in the report.
6. If a finding concerns this plugin's rules or skills, add a `## For /evolve` section
   naming the rule or skill id, and say so in your reply.
7. Report the counts back: sources scanned, candidates found, duplicates dropped, entries
   written, alerts raised.

## Constraints

NEVER scan without a program file. An unbounded scan is a web crawl with a bill.
NEVER exceed the program's stated search budget. Budget exhausted → stop and report partial.
ALWAYS deduplicate against ai-knowledge BEFORE writing an entry or a report line, never after.
NEVER write a claim without a source link or an explicit `[unverified]` marker.
NEVER repeat a finding that a previous report already carried — the report is a DELTA.
NEVER write outside `~/worklogs/research/` and the ai-knowledge base.
ALWAYS put the ALERT line at the very top of the report when the program's alert condition
fires, never buried in a section.
NEVER treat a forum, Reddit, or HN thread as truth — it is a lead, and the report must say so
until an official source or the tool's own source confirms it (rule 016).
ALWAYS report a same-day rescan as an empty delta rather than regenerating yesterday's content.

## Few-shot example

**Input:** `/research-scan` in `~/Projects/ai-tools`, program present, last report 2026-08-31.

**Reasoning:** Program resolves at rung 2. Budget 15 searches. Nine candidates come back;
six already sit in ai-knowledge unchanged and are dropped before anything is written. One is
a competitor shipping config measurement — the program's alert condition.

**Output:**
```
[RESEARCH-SCAN] ai-tools
  sources scanned: 5/5      searches used: 12/15
  candidates: 9   duplicates dropped: 6   new entries: 3   alerts: 1
  report: ~/worklogs/research/2026/09/2026-09-08-ai-tools.md
  for /evolve: none
⚠️ ALERT: <competitor> shipped per-repo config scoring — the niche is contested.
```

**Input (same day, second run):** `/research-scan`

**Output:**
```
[RESEARCH-SCAN] ai-tools — empty delta, last scan was today. Nothing rescanned.
```
