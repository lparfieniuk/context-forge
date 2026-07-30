# ContextForge

[![Plugin Audit](https://github.com/reghis86/context-forge/actions/workflows/plugin-audit.yml/badge.svg)](https://github.com/reghis86/context-forge/actions/workflows/plugin-audit.yml)
[![Version](https://img.shields.io/badge/version-1.1.0-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Node](https://img.shields.io/badge/node-%3E%3D20-brightgreen)](.nvmrc)

> Deterministic context engineering for AI coding agents — structure over search, tokens over brute force.

A Claude Code (and, partially, Cursor) plugin that treats the context window as a **budget** rather than
a bucket. 18 rules, 20 skills, 1 sub-agent, 11 hooks, 31 shell tools — all built around one idea: the
cheapest executor that produces a correct result should do the work, and everything else belongs on disk.

---

## The problem

Coding agents are expensive in ways that are easy to miss:

| Symptom | Cost |
|---|---|
| Reading whole files to locate one class | ~30k tokens for a ~50-token answer |
| Spawning an LLM sub-agent for a job `rg` could do | 200–5,000 tokens instead of ~0 |
| Losing architectural decisions to context compaction | Re-derived every session |
| Retrying a broken action indefinitely | Unbounded cost, no diagnosis |
| Tool output accumulating unbounded in the window | Context rot: recall degrades *before* the token limit |

ContextForge attacks each one with a deterministic mechanism rather than a suggestion: a pre-built symbol
manifest, a routing tier table with hooks that block violations, a filesystem-backed worklog, a two-strike
circuit breaker, and enforced output-compression thresholds.

## Six pillars

1. **Structure over search** — a pre-built Shadow Index manifest answers "where is X?" for ~50 tokens instead of ~30k of raw reads. No vector DB, no embeddings, no probabilistic retrieval.
2. **Token budget awareness** — effective context is treated as 60–70% of the advertised window. Sub-agents multiply cost; escalation must be earned.
3. **Filesystem as memory** — external YAML files are authoritative. The context window is a working register, not a database.
4. **Cheapest correct tier** — CLI (Tier 0) before scripts (Tier 1) before Haiku (Tier 2) before Sonnet (Tier 3).
5. **Fail loud, fail fast** — two identical failures trigger `[CIRCUIT_BREAKER_HALT]`; every halt writes an auditable YAML failure ledger.
6. **Hard constraints over soft guidance** — rules speak in ALWAYS / NEVER / BANNED, and hooks enforce the ones that can be enforced deterministically.

---

## Requirements

- **Claude Code** (full support) or **Cursor** (partial — rules + `cf-scribe` agent + Shadow Index only; no hooks, no skills)
- [Superpowers](https://github.com/obra/superpowers) ≥ 5.0.0 — required co-dependency (workflow skills are delegated to it, not reimplemented)
- Node.js ≥ 20 — for the convert pipeline, manifest generation, and tests (`.nvmrc` pins 22)
- [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`) — a hook blocks `grep` and suggests the `rg` equivalent
- Bash
- *Optional:* a `code-review-graph` MCP server for impact analysis — degrades gracefully to `rg` when absent

## Installation

```bash
git clone https://github.com/reghis86/context-forge ~/.claude/plugins/context-forge
cd ~/.claude/plugins/context-forge
npm install
npm run convert          # distribute core/ → skills/, agents/, .claude/, .cursor/
```

Point the Shadow Index at the repositories you actually work in — `config/manifest-repos.json`:

```json
{
  "repos": [
    { "name": "my-repo", "rel_path": "../my-repo", "paths": ["src/", "libs/"] }
  ]
}
```

Then start a Claude Code session. The SessionStart hook prints a `CONTEXTFORGE STATUS` block —
manifests, task type, capacity estimate, tier availability. If you see it, you're installed.

## Quick start

```
/shadow-lookup BillingFacade     # symbol → file path, ~50 tokens, zero LLM cost
/safe-exec npm run build         # >5 KB output is written to disk and summarized
/pack-context "billing|invoice"  # bundle 3–15 related files into one XML block
/help                            # every skill, grouped, with live system status
```

---

## Architecture

```
                        ┌──────────────────┐
                        │  core/_index.yaml │   single source of truth
                        └─────────┬────────┘
        ┌─────────────┬───────────┼───────────┬──────────────┐
        ▼             ▼           ▼           ▼              ▼
   core/rules/   core/skills/ core/agents/ core/scripts/  hooks/
   18 × YAML+MD  20 × SKILL   1 × agent    31 × .sh       11 scripts
        │             │           │
        └─────────────┴───────────┘
                      │  npm run convert
        ┌─────────────┴──────────────┐
        ▼                            ▼
  Claude Code                     Cursor
  .claude/rules/                  .cursor/rules/*.mdc
  skills/  agents/                .cursor/agents/

  ── state lives outside the window ──────────────────────────
  <IDE_DIR>/shadow/<repo>/_manifest.lightweight.yaml   symbols
  <IDE_DIR>/lessons/YYYY/MM/DD/…                       failure ledgers
  <IDE_DIR>/evolve/pending/                            rule proposals
  ~/worklogs/{INDEX,tickets,plans,learnings,runs}      decisions & recall

  ── delegates ───────────────────────────────────────────────
  Superpowers        → TDD, debugging, planning, code review, worktrees
  code-review-graph  → impact radius (optional MCP, rg fallback)
```

Nothing in `skills/`, `agents/`, `.claude/rules/`, or `.cursor/` is hand-written — it is all generated
from `core/` by `scripts/convert.ts`. Edit the source, run convert, commit both.

---

## Rules (18)

Every rule carries a `## SYSTEM CONSTRAINTS` block of hard ALWAYS/NEVER statements, at least one
few-shot example with explicit reasoning, and a validation-gate checklist. All IDs are `cf-`-prefixed
so they cannot collide with Superpowers or your own rules.

| # | ID | Mode | What it enforces |
|---|---|---|---|
| 001 | cf-token-efficiency | always | Lead with the conclusion; diff-only edits; tables over JSON; no filler |
| 002 | cf-shadow-index | always | Manifest before raw reads; 3-step lookup escalation; IDE auto-detect |
| 003 | cf-tier-routing | always | Cheapest-tier routing; Haiku-first; concurrency ceilings; Scribe dispatch |
| 004 | cf-circuit-breaker | always | Two-strike halt; failure-ledger YAML; DEGRADED read-only state |
| 005 | cf-code-search | intelligent | `rg` only (`grep` banned); progressive disclosure: count → files → lines |
| 006 | cf-prompt-caching | intelligent | KV prefix stability; static-first placement; TTL and breakpoint budget |
| 007 | cf-context-loading | intelligent | Task-type detection from branch; minimal rule set per task type |
| 008 | cf-worklog | intelligent | State externalization; append gates; `supersedes` backlinks for reversals |
| 009 | cf-module-index | intelligent | `_index.yaml` first; source path ≠ installed path |
| 010 | cf-context-budget | always | 60–70% effective capacity; threshold actions at 70% / 80% |
| 011 | cf-kernel-prompts | intelligent | KERNEL template (Context/Task/Constraints/Format/Verify) for every sub-agent |
| 012 | cf-rule-authoring | intelligent | Dual YAML+MD format; nine golden rules; mandatory validation gate |
| 013 | cf-interleaved-thinking | intelligent | Adaptive thinking + `output_config.effort` per model; no `budget_tokens` |
| 014 | cf-tool-result-clearing | intelligent | Clear re-fetchable tool results at 30k; typed `keep` params |
| 015 | cf-mcp-tools | intelligent | MCP routing; snapshots over screenshots; no uncapped crawls |
| 016 | cf-research-escalation | intelligent | Local-first, then bounded web research; forums are leads, docs are truth |
| 017 | cf-cloud-execution | intelligent | TTL + cancel path on metered jobs; verify digests and control-plane writes |
| 018 | cf-cost-model | intelligent | Routing priced in dollars; Batch API for non-interactive work; tokenizer drift |

**Measured cost** (`bash core/scripts/tools/benchmark-tokens.sh`): always-on rules ≈ **2,500 tokens**;
all 18 rules ≈ 10,500 tokens. `intelligent` rules load only when the task matches.

## Skills (20)

| Skill | Category | Tier | What it does |
|---|---|---|---|
| `shadow-lookup` | discovery | 0 | Symbol → file path from the manifest. Pure shell, zero LLM cost |
| `extract-signatures` | discovery | 1 | TypeScript/PHP method stubs without bodies (~500–2k tokens) |
| `refresh-manifest` | discovery | 1 | Regenerate Shadow Index manifests; dual-writes `.claude` + `.cursor` |
| `pack-context` | discovery | 2 | Keyword-filtered XML bundle of 3–15 interrelated files |
| `safe-exec` | execution | 1 | Run a command; spill >5 KB output to a log file and return a summary |
| `log-analyzer` | execution | 1 | Distill a build/test log to root cause + file + one-line fix |
| `clear-context` | execution | 1 | Emit the correct `context_management.edits` clearing parameters |
| `compile-wiki` | execution | 2 | Generate a persistent per-domain wiki (Karpathy pattern) |
| `task-init` | workflow | 1 | Create a ticket worklog, detect branch and task type, update the index |
| `update-worklog` | workflow | 1 | Append a decision/phase entry, with a skip-on-trivial gate |
| `diary` | workflow | 1 | Append a decision/outcome entry for the self-evolving loop |
| `session-learnings` | workflow | 2 | Capture cross-session observations and rule suggestions |
| `record-failure` | workflow | 1 | Write a sharded failure ledger; detect the 3-strike pattern |
| `evolve` | workflow | 3 | Reviewer panel over accumulated signal; writes human-gated proposals |
| `evolve-apply` | workflow | 1 | Apply an approved proposal; convert + audit; auto-revert on failure |
| `pre-review` | workflow | 1 | Gather diff context, then delegate to Superpowers' code review |
| `end-session` | workflow | 1 | Close-out sequence: diary + learnings, commit, merge |
| `optimize-rules` | admin | 2 | Token audit across all rules; suggest activation-mode changes |
| `plugin-audit` | admin | 1 | Run the full index/parity/surface audit gate |
| `help` | admin | 0 | List every skill with live system status. Zero LLM cost |

## Agent (1)

| Agent | Model | Role |
|---|---|---|
| `cf-scribe` | Haiku | Observation masking — compresses large tool output into a bounded `[SCRIBE OUTPUT]` block before the primary context ever sees it. Read-only; never mutates files |

## Hooks (11)

Hooks are what make the rules more than advice — the blocking ones fail the tool call outright.

| Event | Script | Blocking | Purpose |
|---|---|---|---|
| SessionStart | `session-start.sh` | no | IDE detection, manifest freshness, task type, capacity estimate, evolve signal count |
| PreToolUse · Bash | `enforce-rg.sh` | **yes** | Reject `grep`; print the `rg` equivalent |
| PreToolUse · Bash | `pre-commit-review.sh` | **yes** | Reject `git commit` without a review marker |
| PreToolUse · Agent | `enforce-tier-routing.sh` | **yes** | Reject a sub-agent spawn when a Tier 0/1 alternative exists |
| PostToolUse · Bash | `run-log-writer.sh` | no | Log significant calls to `~/worklogs/runs/` as self-evolve signal |
| PostToolUse · Bash | `wiki-nudge.sh` | no | Suggest `/compile-wiki` when a domain is read repeatedly |
| PostToolUse · MCP | `mcp-context-guard.sh` | no | Flag oversized MCP payloads for clearing (rule 014) |
| SubagentStop | `subagent-telemetry.sh` | no | Track spawns, model, duration, tier; warn at the Tier-3 ceiling |
| PreCompact | `pre-compact-anchor.sh` | no | Re-inject top constraints before compaction (lost-in-the-middle mitigation) |
| SessionEnd | `diary-capture.sh`, `session-end-reminder.sh` | no | Write the session diary entry; report stats and remind about learnings |

---

## Tier routing

Every task is routed to its minimum-cost executor. Escalation requires *evidence*, not preference.

| Tier | Executor | Token cost | Max concurrent | Use for |
|---|---|---|---|---|
| 0 | Inline CLI — `rg`, `diff`, `wc`, `git`, `shadow-lookup.sh` | ~0 | unlimited | One-off mechanical queries, yes/no checks |
| 1 | Shell scripts in `core/scripts/tools/` | ~50 amortized | unlimited | Recurring checks where a script already exists |
| 2 | `Task(model: "haiku")` | ~200–1,000 | 4 | Multi-file reasoning that needs LLM judgment |
| 3 | `Task(model: "sonnet")` | ~600–5,000 | 2 | Architecture and planning decisions |

**Escalating Haiku → Sonnet requires all three:** the task spans >5 interrelated files across
architectural layers, *and* needs semantic reasoning beyond pattern application, *and* Haiku already
returned `[ESCALATE]` or failed. The same shape of gate guards Sonnet → Opus at >10 files.

A sub-agent's response is capped at 2,000 tokens, and raw tool output is never passed between agents.

## Self-evolving loop

The plugin observes its own operation and proposes its own changes — but never applies them unattended.

```
run logs + diary entries + failure ledgers        (hooks, automatic)
        │
        ▼  signal threshold reached → SessionStart prints "run /evolve"
   /evolve  → pre-filter → evidence gate → Fit/Cost/Risk reviewer panel (Haiku)
        │
        ▼  proposals: ADD | MODIFY | MERGE | PRUNE | REJECT
   <IDE_DIR>/evolve/pending/<id>.yaml             ← a human reads this
        │
        ▼  explicit approval only
   /evolve-apply <id>  → patch core/ → convert → audit → revert if audit fails
```

`/evolve` **never** edits a rule or skill. It writes proposals. Three occurrences of the same failure
slug across sessions is what triggers it in the first place (rule 004's 3-strike escalation).

---

## Repository layout

| Path | Contents | Edit? |
|---|---|---|
| `core/_index.yaml` | Master module map — every rule, skill, agent, script | yes, then validate |
| `core/rules/<NNN>-cf-<id>.{md,yaml}` | Rule source: content + metadata | **yes** |
| `core/skills/<id>/SKILL.md` | Skill source | **yes** |
| `core/agents/<id>.{md,yaml}` | Agent source | **yes** |
| `core/scripts/tools/*.sh` | Tier 0/1 shell tooling (31 scripts) | **yes** |
| `hooks/*.sh`, `hooks/hooks.json` | Enforcement hooks | **yes** |
| `scripts/*.ts` | Convert pipeline, manifest generator, test suite | **yes** |
| `docs/adr/` | Architecture decision records | **yes** |
| `skills/`, `agents/`, `.claude/rules/`, `.cursor/` | Generated by convert | **never** |

## Development

```bash
npm run convert          # core/ → all installed IDE paths (run after every core/ edit)
npm test                 # vitest — 58 tests over hooks, scripts, and the convert pipeline
npm run validate-index   # _index.yaml consistency; fix every ERROR before committing
npm run test:audit       # full plugin audit gate (index + parity + surface + doc claims)

bash core/scripts/tools/benchmark-tokens.sh              # token cost per artifact
bash core/scripts/tools/benchmark-tokens.sh --baseline   # snapshot to core/benchmarks/
```

CI runs the audit gate on every push (`.github/workflows/plugin-audit.yml`).

Adding a module: register it in `core/_index.yaml` **first**, create the source files, run
`validate-index`, then `convert`. The audit fails on an unregistered artifact by design.

---

## Relationship to Superpowers

The two plugins are orthogonal and are meant to run together. Superpowers teaches an agent *what to do*;
ContextForge governs *how much context that costs*.

| Concern | Owner |
|---|---|
| TDD, debugging, planning, code review, git worktrees | Superpowers |
| Token efficiency and output constraints | ContextForge |
| Symbol lookup, Shadow Index, manifests | ContextForge |
| Tier routing and cost hierarchy | ContextForge |
| State externalization and worklogs | ContextForge |
| Failure ledgers and circuit breakers | ContextForge |
| Impact radius / blast radius | `code-review-graph` MCP (optional) |

ContextForge hooks fire before Superpowers hooks. Both skill sets stay available; the `cf-` prefix
guarantees no name collisions.

## FAQ

**Why no vector search?**
A manifest lookup is deterministic, auditable, and costs ~50 tokens. Embedding-based retrieval is
probabilistic and costs more per query for worse accuracy on structured code, where the ground truth
(a symbol table) can simply be precomputed. Vector RAG is explicitly banned by rule 002.

**What do the benchmarks actually measure?**
`benchmark-tokens.sh` measures the **static context cost** of the plugin's own artifacts — lines, words,
and estimated tokens per rule/skill/agent, with baselines committed under `core/benchmarks/` so
regressions across versions are visible. It does **not** measure end-to-end session savings; that number
depends entirely on task mix and escalation rate, and no honest single figure exists for it. The
per-mechanism claims (a manifest lookup at ~50 tokens versus reading source files) are structural, not
statistical.

**Does it work in Cursor?**
Partially. Cursor gets the 18 rules as `.mdc` files, the `cf-scribe` agent, and dual-written Shadow Index
manifests. Skills and hooks are Claude Code only, so enforcement in Cursor is rule-based (model
compliance) rather than hook-based (deterministic).

**Why are `skills/` and `core/skills/` duplicated in the repo?**
`core/` is source; the rest is build output committed for zero-install use of the plugin. Editing the
generated copy is a no-op — the next `npm run convert` overwrites it.

## Project history

ContextForge was built and used privately between April and July 2026, iterating against real daily
work rather than as a greenfield design. Version 1.1.0 is the first public cut, published as a single
commit: the original history was tied to a private working environment and was not carried over.

What that history produced is still visible in the repository rather than in the commit graph —
[`CHANGELOG.md`](CHANGELOG.md) records each version's reasoning including what was retired and why,
and [`docs/adr/`](docs/adr/) holds the architecture decision records behind the design choices
(extended cache TTL, model-ID anchoring, agent size reduction, context-editing API integration).
Development continues in the open from here.

## Contributing

`core/` is source; everything else is generated by `npm run convert`. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the edit → convert → audit loop, the rule-authoring contract,
and the macOS/Linux shell portability rules. Security policy and threat model:
[SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE).
