---
name: compile-wiki
description: >
  Karpathy Wiki pattern: reads source files for a domain, generates structured wiki pages (one per major concept/module), and builds an index. Stored persistently so future sessions read the index (~500 tokens) instead of raw source files.
  <example>
  Context: Starting work on the billing domain and need persistent reference docs.
  user: "/compile-wiki --domain billing --sources libs/billing/src/"
  assistant: "Running compile-wiki for billing domain — generates wiki pages and index at ~/worklogs/wiki/billing/."
  </example>
model: sonnet
---

## What This Does

Implements the Karpathy Wiki pattern (compile once, query cheap). Reads source files in the specified path, synthesizes structured wiki pages — one per major concept or module — and creates a `wiki/<domain>/index.md` with a summary table and links to individual pages. Complements the Shadow Index: Shadow = WHERE (symbols), Wiki = WHAT (concepts). Pages are stored persistently at `~/worklogs/wiki/<domain>/` across sessions.

## When to Use

PROACTIVELY invoke this without waiting to be asked — it is intelligent-mode, not manual-only — when:

- pack-context has been run 2+ times this session and no wiki has been compiled yet anywhere under `~/worklogs/wiki/` — the exact deterministic (count-based, not path-aware) signal the `wiki-nudge.sh` hook also checks, see `hooks/wiki-nudge.sh`. Ideally the calls target overlapping `--search-path`/`--pattern` values, but the hook can't cheaply verify that, so treat any 2nd call as the trigger
- Starting substantial work on a domain with no existing wiki and no plan to touch it only once
- Shadow Index covers symbol locations but the task needs narrative/conceptual understanding, not just WHERE
- Team onboarding: generate wiki so new developers can orient quickly

Can also be invoked explicitly: `/compile-wiki --domain <domain> --sources <path>`.

## How to Use

Step 1: Identify the domain and source path.

Step 2: Use pack-context to gather source files (if not already in context).

```bash
bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/pack-context.sh \
  --pattern "<domain-pattern>" \
  --search-path <sources-path>
```

Step 3: For each major concept identified in the source bundle, generate a wiki page at `~/worklogs/wiki/<domain>/<concept-slug>.md`. Each page contains:
- Purpose summary (2-3 sentences)
- Key classes/functions with brief descriptions
- Data flow or lifecycle notes
- Dependencies and integration points

Step 4: Generate the index file at `~/worklogs/wiki/<domain>/index.md` using the format below.

Step 5: Write a generation metadata footer to the index (timestamp, source path, file count, symbol count).

Step 6: Report completion with the [WIKI COMPILED] envelope.

## Output Format

Index file (`wiki/<domain>/index.md`):

```markdown
# Billing Domain — Wiki Index

| Page | Summary |
|------|---------|
| [billing-facade](billing-facade.md) | Orchestrates billing actions via NgRx store |
| [billing-effects](billing-effects.md) | Side effects for API calls, error handling |
| [subscription-model](subscription-model.md) | Subscription lifecycle, plan tiers, upgrades |

Generated: 2026-04-14 | Sources: libs/billing/src/ | Files: 12 | Symbols: 47
```

Completion envelope (returned to agent):

```
[WIKI COMPILED]
- Domain: billing
- Pages generated: 3
- Index: ~/worklogs/wiki/billing/index.md
- Sources: libs/billing/src/ (12 files, 47 symbols)
[END WIKI COMPILED]
```

## Constraints

- ALWAYS consider this proactively per the trigger conditions above — do NOT wait for explicit `/compile-wiki` invocation when the signal is already present
- NEVER regenerate an existing wiki without `--force` flag — check index timestamp first
- ALWAYS generate one page per major concept/module, not one page per file
- ALWAYS store wiki at `~/worklogs/wiki/<domain>/` — NEVER in the source repo
- NEVER include raw code in wiki pages — summaries and API descriptions only
- ALWAYS include generation metadata (timestamp, source path, file/symbol counts) in the index footer
- NEVER use pack-context for more than 15 files in a single wiki compilation pass — split large domains into sub-domains
