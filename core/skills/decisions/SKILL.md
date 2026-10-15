---
name: decisions
description: Lists every choice made during the current work that the agent is not confident of. Manual only — /decisions. Do NOT use to record a decision (that is adr-verbatim or diary).
model: inherit
disable-model-invocation: true
---

## What This Does

Surfaces the agent's silent guesses so the user can check the risky ones before they ship.


List every choice made in this session's work that you are NOT confident of: assumptions,
defaults picked without asking, APIs or flags not verified against source, edge cases skipped,
scope cut.

| # | Choice | Why unsure | What would settle it | Risk if wrong |
|---|---|---|---|---|

- Order by risk, highest first. Include `file:line` where the choice lives.
- Be honest: a choice verified by a test or a source read does not belong here.
- Nothing to list → say so in one line, and name the one verification you skipped, if any.

Adapted from github.com/davidondrej/skills (MIT).

## Constraints

NEVER list a choice already verified by a test or a source read. ALWAYS order by risk.

## Few-shot

**Input:** "/decisions"
**Output:** | 1 | `LC_NUMERIC=C` only in 2 scripts | other awk %f callers not audited | `rg 'printf.*%\.[0-9]f'` | locale commas in output |
