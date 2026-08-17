# ContextForge

> Deterministic context engineering for AI coding agents — structure over search, tokens over brute force.

## Plugin Identity

**Name:** ContextForge (`context-forge`)
**Version:** 1.1.0
**Primary IDE:** Claude Code (full support)
**Secondary IDE:** Cursor (rules + `cf-scribe` agent only)

## Core Principles (6 Pillars)

1. **Structure Over Search** — Pre-built Shadow Index manifests eliminate expensive raw file reads (~50 tokens vs ~30k).
2. **Token Budget Awareness** — Every token has a cost. Effective window = 60–70% of nominal. Sub-agents multiply cost 15x.
3. **Filesystem as Memory** — External files are authoritative. Context window is a working register, not a database.
4. **Cheapest Correct Tier** — Use CLI (Tier 0) before scripts (Tier 1) before Haiku (Tier 2) before Sonnet (Tier 3).
5. **Fail Loud, Fail Fast** — Two identical failures = `[CIRCUIT_BREAKER_HALT]`. Every failure produces an auditable YAML ledger.
6. **Hard Constraints Over Soft Guidance** — Rules use ALWAYS/NEVER/BANNED. Hooks enforce deterministically.

## Rule Summaries

| # | ID | Mode | Top 2 Constraints |
|---|---|---|---|
| 001 | cf-token-efficiency | always | ALWAYS lead with conclusion. NEVER use conversational filler. |
| 002 | cf-shadow-index | on-demand | NEVER read raw source for discovery — manifest first. NEVER skip Tier 1. |
| 003 | cf-tier-routing | always | NEVER spawn Task() when Tier 0/1 exists. NEVER >2 concurrent Tier 3. |
| 004 | cf-circuit-breaker | always | NEVER retry after 2nd identical failure. ALWAYS generate Failure Ledger YAML. |
| 005 | cf-code-search | always | NEVER use `grep` — BANNED, use `rg`. NEVER use `--json`/`--vimgrep` with rg. |
| 006 | cf-prompt-caching | on-demand | NEVER interleave static files with conversation. NEVER put timestamps in system prompt. |
| 008 | cf-worklog | on-demand | ALWAYS externalize to YAML scratchpads. ALWAYS read INDEX.yaml at session start. |
| 009 | cf-module-index | on-demand | NEVER invent paths — ALWAYS check `core/_index.yaml` first. NEVER assume installed=source. |
| 010 | cf-context-budget | always | ALWAYS treat capacity as 60–70% of advertised window. NEVER spawn Tier 3 without checking capacity. |
| 011 | cf-kernel-prompts | on-demand | ALWAYS use KERNEL template for every Task() prompt. NEVER spawn Task() with vague prompt. |
| 012 | cf-rule-authoring | on-demand | ALWAYS use hard constraints: ALWAYS/NEVER/BANNED. NEVER mix constraints with guidance. |
| 013 | cf-interleaved-thinking | on-demand | ALWAYS pass `effort` via `output_config` (never inside `thinking`). NEVER use `budget_tokens` on Opus 4.6+/Fable (400) — use adaptive thinking + effort. |
| 014 | cf-tool-result-clearing | on-demand | NEVER let tool results exceed 30K tokens. NEVER use LLM summarization for re-fetchable tool results. |
| 015 | cf-mcp-tools | on-demand | NEVER use an MCP tool when a Tier 0/1 alternative exists. NEVER run an uncapped Firecrawl crawl. |
| 016 | cf-research-escalation | on-demand | ALWAYS local-first before web; research bounded (≤2 queries) before the halt. NEVER treat Reddit/forum as truth — lead, verify against docs/source. |
| 017 | cf-cloud-execution | on-demand | NEVER submit a paid remote job without TTL + cancel path. NEVER re-push a mutable image tag and assume workers picked it up. |
| 018 | cf-cost-model | on-demand | ALWAYS reason routing cost in dollars (doc-verified prices). NEVER price output like input (5x); ALWAYS Batch non-interactive work (50% off). |
| 019 | cf-critical-response | always | NEVER open with praise/agreement; verdict first. ALWAYS carry the counter-position; reverse only on evidence, never on pushback. |

## Skills

| Category | ID | Tier | Model | Description |
|---|---|---|---|---|
| discovery | extract-signatures | 1 | haiku | Extract TypeScript/PHP function signatures live from source |
| discovery | pack-context | 2 | sonnet | Bundle multiple files into XML context block |
| discovery | refresh-manifest | 1 | haiku | Regenerate lightweight shadow manifest for symbol lookup |
| discovery | shadow-lookup | 0 | none | Zero-cost manifest symbol lookup |
| execution | safe-exec | 1 | haiku | Run commands with automatic output compression (>5KB) |
| execution | log-analyzer | 1 | haiku | Distill error logs to RCA — root cause + fix |
| execution | compile-wiki | 2 | sonnet | Compile contextual wiki via Karpathy pattern |
| execution | clear-context | 1 | none | Orchestrate tool result clearing and server-side compaction |
| workflow | task-init | 1 | haiku | Initialize Jira task worklog at session start |
| workflow | update-worklog | 1 | haiku | Append entry to active ticket worklog |
| workflow | session-learnings | 2 | sonnet | Capture session learnings and pattern suggestions |
| workflow | record-failure | 1 | haiku | Log circuit breaker failure with YAML ledger |
| workflow | diary | 1 | haiku | Append decision/outcome entry to session diary |
| workflow | evolve | 3 | sonnet | Self-evolving loop reviewer panel — writes human-gated proposals |
| workflow | evolve-apply | 1 | haiku | Apply a human-approved /evolve proposal; patch + convert + audit, revert on failure |
| workflow | pre-review | 1 | haiku | Pre-commit review delegating to superpowers:requesting-code-review |
| workflow | end-session | 1 | haiku | Session close-out: diary + learnings, commit, merge working branch |
| workflow | session-handoff | 1 | haiku | Compress live state into a paste-able payload so `/clear` costs no context |
| discovery | rule-index | 0 | haiku | Load an on-demand rule before the action it governs |
| admin | optimize-rules | 2 | sonnet | Audit and optimize rules for token efficiency |
| admin | plugin-audit | 1 | none | Validate plugin/index/parity gates via audit tooling |
| admin | help | 0 | none | List available skills grouped by category |

## Agents

| ID | Model | Role |
|---|---|---|
| cf-scribe | haiku | Observation masking — compresses large outputs before primary context reads them |

## Agent Routing Tier Table

| Tier | Executor | Token Cost | Max Concurrent | When |
|------|----------|------------|---------------|------|
| 0 | Inline CLI (rg, diff, wc, git) | ~0 | Unlimited | One-off queries, yes/no checks |
| 1 | Scripts (`core/scripts/tools/`) | ~50 amortized | Unlimited | Recurring checks, script exists |
| 2 | `Task(model: "haiku")` — Haiku | ~200–1k | 4 | Multi-file reasoning, LLM judgment |
| 3 | `Task(model: "sonnet")` — Sonnet | ~600–5k | 2 | Architecture, planning, complex reasoning |

## Source of Truth

| Artifact | Edit Here | Never Edit |
|----------|-----------|-----------|
| Rules | `core/rules/<NNN>-cf-<id>.md` | `.cursor/rules/*.mdc` |
| Skills | `core/skills/<id>/SKILL.md` | `skills/<id>/SKILL.md` |
| Agents | `core/agents/<id>.md` | `agents/<id>.md`, `.cursor/agents/<id>.md` |
| Module map | `core/_index.yaml` | anywhere else |

Run `npm run convert` after editing source files to propagate changes to installed paths.

## Rule Activation Contract

`.claude/rules/` is loaded as a project instruction on EVERY session — a file there costs its full token count unconditionally. Only `activation: always` rules earn a slot (6 rules, 5491 tokens measured 2026-08-18). The 12 `on-demand` rules (002 shadow-index among them) set `installed_claude: null` and are reached through the `rule-index` skill or read directly from `core/rules/`.

Rule 002 (shadow-index) left the always-on set on 2026-08-18: 862 tokens in every session of every repo to describe a protocol most sessions never enter. `hooks/session-start.sh` now prints one line carrying the operative part — the Tier 0 lookup command when a manifest exists, the command that creates one when it does not (and only in repos with ≥30 source files). Counter-position on record: without the rule resident, an agent that ignores that line will read raw source and never reach for the manifest; the line is the whole mitigation, so keep it actionable.

Rule 007 (context-loading) was deleted, not demoted. Its decision table routed on `Domain`/`Integration`/`Boundary` rule categories this plugin never had, and nothing consumed its output — `hooks/session-start.sh` printed a `rule_budget` figure no code or rule read. Rule loading is routed by concern through `rule-index`, which is precise where a branch prefix is a guess.

`convert.ts` refuses to install a non-`always` rule, and `scripts/rule-activation.test.ts` fails if one regains an `installed_claude` path, if `rule-index` points at a missing file, or if `.claude/rules/` holds a file the index does not list as always-on — `convert.ts` writes but never prunes, so a demoted rule's installed copy kept billing until the directory itself was measured. Measured 2026-08-17: installing all of them always-on cost **14968 tokens per session** for rules that were authored to load conditionally.
