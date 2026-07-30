# Changelog

## [Unreleased]

## [1.1.0] - 2026-07-30

First public release. Everything below was developed privately between
2026-04-14 and 2026-07-30 and is published here as one cut; see
[README — Project history](README.md#project-history).

### Portability and tooling (2026-07-30)

- **`stat` fallback order** (`statusline.sh`, `bootstrap-agent.sh`) — `stat -f %m FILE` means "filesystem status" on GNU coreutils, which takes `%m` as an operand, writes filesystem info to stdout *and* exits non-zero. A `stat -f … || stat -c …` chain therefore concatenated that output with the fallback and broke the arithmetic that followed. GNU is now tried first (BSD has no `-c` and fails cleanly), with a numeric guard on the result.
- **Marketplace parity suite** now skips when `../.local-marketplace/` is absent — it exists only on a machine with the plugin installed locally, so the suite could never pass on a fresh clone or in CI.
- **CI runs the canonical audit gate** (`npm run test:audit`); the partial duplicate `scripts/test-audit.sh` is deleted.
- **Dependencies:** `tree-sitter` pinned to `^0.21.1` (the peer the grammar packages declare — `0.22.4` made `npm ci` fail on a strict resolve); `vitest` 1.6 → 4, clearing the vite/esbuild advisory chain (0 vulnerabilities).
- **Plugin cache path** is read from `.claude-plugin/plugin.json` instead of a hardcoded version string, so it no longer drifts on a version bump.

### Added

- **Rule 016 `cf-research-escalation`** (intelligent) — turns the circuit breaker from "give up at the 2nd failure" into "research at the 1st, halt at the 2nd if still stuck". On a first failure during autonomous work: local-first (source/docs/manifest), then bounded routed web research (GitHub issues + official docs as the authority; Reddit/forum/StackOverflow as lead-not-truth, verified before acting), ≤2 queries + ≤3 fetches, research trace recorded in the failure ledger. Cross-referenced from `004-cf-circuit-breaker` (failure chain step 1) and `015-cf-mcp-tools` (`firecrawl_research_search_github`/`firecrawl_search` mechanism; `gh`/`WebFetch` Tier-0 preferred).
- **Self-evolving loop v2:** `/diary` enrichment skill (appends decision/outcome entries to session diaries); `/evolve` 4-reviewer panel orchestrator (Fit/Cost/Risk Haiku panel, gated on Evidence, writes human-gated ADD/MODIFY/MERGE/PRUNE/REJECT proposals); `/evolve-apply` human-gated apply skill (patches core/, runs convert + audit, reverts on audit failure).
- `diary-capture.sh` SessionEnd hook (writes baseline diary entry) and a SessionStart self-evolve readiness surface ("N new signals — run /evolve").
- `evolve-signal.sh` Tier 0 pre-filter — count-based signal delta, no LLM call, to decide when `/evolve` is worth running.
- **Evolve outcome ledger:** `evolve-apply.sh` appends one TSV row per attempt to `.claude/evolve/ledger.tsv` (`applied|reverted|reverted-patch`); `/evolve` reads it Tier-0 to skip already-reverted verdict+target pairs and applies a simplicity criterion in the Cost reviewer (autoresearch `results.tsv` pattern).
- **`quality-score.sh`** (Tier 1) — deterministic composite quality score for rules (7 dims) and skills (6 dims) using the full-denominator model (an unmeasured dimension stays in the denominator → honest coverage, never renormalized); wired into `/optimize-rules` as a reporter.
- **`statusline.sh`** — opt-in one-line Claude Code statusLine: model, cwd+branch, context-budget % (rule 010), cache warmth (transcript mtime vs the 5-min TTL, rule 006), session cost. ASCII-only, never crashes the prompt.
- **`session-digest.sh`** + SessionStart wiring — between-session git working-tree digest (changed/staged/untracked, ahead/behind, last commit) plus a confidence-gate reminder (verification-before-completion).
- **`mcp-context-guard.sh`** (PostToolUse, matcher `mcp__.*`) — tracks cumulative MCP output per session and injects an `additionalContext` `/compact` nudge once it crosses a threshold (default 50 KB, `CF_MCP_COMPACT_KB`); operationalizes rule 015 against MCP context bloat.
- **`supersedes` worklog backlink** (rule 008-cf-worklog) — a new YAML worklog entry can backlink an earlier one it reverses via `supersedes: "<ts>"`, so readers treat the old entry as historical instead of current truth (MemPalace-inspired, single-field, no graph/DB).
- **`wiki-nudge.sh`** (PostToolUse, matcher `Bash`) — deterministic backstop for `/compile-wiki`: fires once per session, on the 2nd `pack-context.sh` call, if no wiki has ever been compiled (`~/worklogs/wiki/` empty). `compile-wiki`'s own `SKILL.md` now documents proactive (intelligent-mode) trigger conditions instead of "triggered manually".

### Changed

- Retired v1 `extract-lessons` + `self-learning-review` skills — folded into the `/evolve` panel.
- `record-failure` 3-strike cross-session pattern now auto-triggers `/evolve` instead of `/extract-lessons`.
- Current surface: **20 skills** across four categories (discovery, execution, workflow, admin) and **11 hooks** across Claude Code event types.

### Fixed

- **Fictional `${CLAUDE_PLUGIN_DATA}` env var** in `compile-wiki` and `safe-exec` docs — not a real Claude Code variable (only Codex/Copilot expose an equivalent, confirmed against a real installed plugin's source). `safe-exec.sh` was actually falling back to `.claude/cache/observations/` *inside the project tree*, which `audit-runtime-artifacts.sh` then flags even though the path is gitignored. Both skills now use `~/worklogs/{logs,wiki}/` — the same out-of-repo convention rule 008-cf-worklog already established — and `log-analyzer`'s example path is corrected to match.

- **API staleness in thinking/effort guidance (rules 010, 011, 013):**
  - `effort` is documented as `output_config: {effort: …}` — it is NOT a field of `thinking` (the previous `thinking: {type: "adaptive", effort: …}` form returns a 400).
  - Adaptive thinking is documented as OFF by default on Opus 4.7/4.8 (must be set explicitly); previously claimed it was on by default.
  - `budget_tokens` corrected: removed (400) on Opus 4.6/4.7/4.8 and Fable 5, deprecated on Sonnet 4.6 — was previously taught as the standard mechanism. `output_config.effort` is the replacement.
- **Context editing beta header (rule 014):** added `context-management-2025-06-27` (required, not added by the SDK); clarified server-side compaction as a separate feature behind beta header `compact-2026-01-12`. Edit-type constants `clear_tool_uses_20250919` / `clear_thinking_20251015` confirmed current.
- **Task tool model aliases (README):** `Task(model: "fast"|"default")` → `Task(model: "haiku"|"sonnet")` to match the current Task tool model enum (`sonnet | opus | haiku | fable`).
- **Blocking hooks wrote `[BLOCKED]` reason to stdout (enforce-rg, enforce-tier-routing, pre-commit-review):** redirected the heredocs to stderr so Claude Code surfaces the reason on exit code 2.

### Changed

- **Model lineup refresh:** Tier 3+ / context-window references updated `claude-opus-4-7` → `claude-opus-4-8` (current Opus); added Fable 5 (`fable`) as the reserved hardest-task model; added `xhigh`/`max` effort levels and the `display: "summarized"` note. Opus 4.8 context note corrected to standard pricing across the full 1M window.
- **Savings claim (README):** "38-50%" marked as a v1.0.0 benchmark predating the June 2026 price changes, pending re-baseline.

## [1.0.0] - 2026-04-14

### Added

- **14 rules** organized into always-on (5) and intelligent (9) tiers:
  - Always-on: cf-token-efficiency (001), cf-shadow-index (002), cf-tier-routing (003), cf-circuit-breaker (004), cf-context-budget (010)
  - Intelligent: cf-code-search (005), cf-prompt-caching (006), cf-context-loading (007), cf-worklog (008), cf-module-index (009), cf-kernel-prompts (011), cf-rule-authoring (012), cf-interleaved-thinking (013), cf-tool-result-clearing (014)
  - Always-on token budget: ~5,500 tokens total; intelligent rules load only on pattern match

- **18 skills** across four categories:
  - Discovery: extract-signatures, pack-context, refresh-manifest, shadow-lookup
  - Execution: safe-exec, log-analyzer, compile-wiki, clear-context
  - Workflow: task-init, update-worklog, session-learnings, record-failure, extract-lessons, self-learning-review, pre-review
  - Admin: optimize-rules, plugin-audit, help

- **1 agent**:
  - cf-scribe — observation masking agent (haiku); compresses large tool outputs (>100 lines / >5 KB) to structured summaries; read-only

- **8 hooks** across 6 Claude Code event types:
  - SessionStart: session-start.sh — IDE detection, manifest freshness check, task-type detection, CONTEXTFORGE STATUS block
  - PreToolUse (Bash): enforce-rg.sh — blocks `grep`, enforces `rg` with equivalent suggestion
  - PreToolUse (Agent): enforce-tier-routing.sh — blocks Task() when Tier 0/1 alternative exists
  - PreToolUse (Bash): pre-commit-review.sh — blocks `git commit` without prior review marker
  - PostToolUse (Bash): run-log-writer.sh — auto-logs significant tool calls to ~/worklogs/runs/
  - SubagentStop: subagent-telemetry.sh — tracks agent spawns, model, duration, tier usage
  - PreCompact: pre-compact-anchor.sh — re-injects critical constraints before compaction (Lost-in-Middle mitigation)
  - SessionEnd: session-end-reminder.sh — prompts /session-learnings capture; reports session statistics

- **Shadow Index** — AST-based manifest generation system:
  - Tree-sitter TypeScript/JavaScript parsing; exports class, interface, enum, function, type, abstract class symbols
  - Dual-write to `.claude/shadow/<repo>/` and `.cursor/shadow/<repo>/`
  - shadow-lookup.sh: ~50 tokens per symbol lookup vs ~30,000 for raw manifest read
  - validate-manifest.sh: age-based + orphan-based staleness detection (exit codes 0=FRESH, 1=STALE, 2=BROKEN)
  - config/manifest-repos.json: configure target repositories and scan paths

- **Worklog System** — cross-session state externalization to `~/worklogs/` (outside git):
  - tickets/ — per-Jira-ticket YAML worklogs with decision history and temporal validity fields
  - plans/ — architect-generated implementation plan files
  - ideas/ and analysis/ — research spikes and technical analysis
  - learnings/ — date-sharded session learning captures
  - runs/ — per-session auto-generated tool call and agent spawn logs (via hooks)
  - agent-diaries/ — per-agent-type persistent pattern memory
  - INDEX.yaml master map; flat log.md for grep-parseable session history
  - Worklog compression: >15 entries triggers Scribe to generate history_summary + last 5

- **Tier Routing** — 4-tier cost hierarchy:
  - Tier 0: inline CLI (rg, diff, wc, git) — ~0 tokens
  - Tier 1: core/scripts/tools/*.sh — ~50 tokens amortized
  - Tier 2: Task(model: "fast") Haiku — ~200-1,000 tokens; max 4 concurrent
  - Tier 3: Task(model: "default") Sonnet — ~600-5,000 tokens; max 2 concurrent
  - KERNEL template (Context/Task/Constraints/Format/Verify) mandatory for all Task() prompts
  - enforce-tier-routing.sh hook: deterministic Tier 0/1 check before any Task() spawn

- **Module System** — core/_index.yaml as single source of truth:
  - Convert pipeline (npm run convert): distributes source from core/ to skills/, agents/, .cursor/rules/
  - validate-index.sh: detects ERRORs (missing files) and DRIFT (installed paths not written)
  - 28+ shell scripts in core/scripts/tools/ for Tier 1 operations
  - CLAUDE.md auto-generated with rule summaries on convert

- **Context Budget Tracking** (cf-context-budget, rule 010):
  - Derived from Context Engineering research: effective capacity = 60-70% of advertised limit
  - Thresholds: warn at 60%, force Scribe at 70%, block Tier 3 spawns at 80%
  - Session-start hook reports initial capacity estimate
  - pre-compact-anchor.sh prevents Lost-in-Middle degradation (10-40% recall loss for middle-positioned content)

- **Circuit Breaker** (cf-circuit-breaker, rule 004):
  - Same action fails twice: emit [CIRCUIT_BREAKER_HALT], enter degraded read-only state
  - Failure ledgers: sharded YAML at `<IDE_DIR>/lessons/YYYY/MM/DD/<2-char-prefix>/<UUID>-<slug>.yaml`
  - 3-strike pattern: third occurrence triggers /extract-lessons skill for rule suggestion drafting
  - NEVER auto-applies lessons — human approval required before rules are updated

### Dependencies

- Required: [Superpowers](https://github.com/obra/superpowers) ≥5.0.0
- Required: Node.js ≥18 (manifest generation via TypeScript AST)
- Required: ripgrep (`rg`) — enforced by hook; grep is blocked
- Required: Bash shell (all hooks and Tier 1 scripts)
- Optional: [code-review-graph](https://github.com/tirth8205/code-review-graph) MCP server — graceful fallback to rg-based heuristics when absent

### Known Limitations

- **Cursor support:** rules + `cf-scribe` agent + shadow index only; hooks and skills require Claude Code; enforcement in Cursor is rule-based (LLM compliance) rather than hook-based (deterministic)
- **Tree-sitter manifest generation:** TypeScript and JavaScript only in v1; additional languages (PHP, Python, Go) planned for v2
- **Self-evolving loop (extract-lessons, agent diaries):** v1 ships the data collection layer (run logs, failure ledgers, agent diaries) and the /extract-lessons skill; the 4-reviewer periodic panel and full agent diary pattern learning are v2 features
- **compile-wiki:** basic version ships in v1; enhanced integration with code-review-graph `generate_wiki_tool` is v2
- **Always-on rules:** Cursor lacks hook enforcement — always-on rules are loaded via .mdc files but agent compliance is not deterministically enforced
