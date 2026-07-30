# ADR-010: Real-Usage Benchmark and Bug Fix Pass

**Date:** 2026-04-26
**Status:** Accepted
**Deciders:** lukasz-parfieniuk

## Context

Static analysis (token counting, format audit, YAML schema validation) was insufficient to catch runtime failures. The first full execution test of ContextForge (all rules, skills, agents, scripts, hooks under actual use) revealed 16 distinct failures across:
- 2 bash compatibility bugs (macOS bash 3.2)
- 1 hook missing testable fallback
- 3 rules with incorrect reference data
- 1 agent with BANNED tool in tool list
- 7 rule YAMLs with missing constraint metadata
- 3 skills with unreachable search patterns
- 3 index files missing installed cursor/claude tracking

These failures would not be caught by static tooling and would cause real operational failures in production use.

## Decision

Fixed all CRITICAL and WARNING issues found during the real-usage test:

### Bash 3.2 Compatibility (CRITICAL)
- **token-counter.sh:** Moved `local` variable declarations to top-level function scope (bash 3.2 on macOS does not permit `local` in subshells)
- **record-failure.sh:** Replaced `${UUID,,}` (bash 4.0+) with portable `tr` alternative for lowercase conversion

### Hook Testability (CRITICAL)
- **pre-compact-anchor.sh:** Added `CLAUDE_PLUGIN_ROOT` fallback detection; hook now testable without environment variable injection

### Rule Data Corrections (WARNING)
- **010-cf-context-budget.yaml:** Corrected context windows for Sonnet/Opus from 200k to 1M; added pricing note for Opus >200k
- **013-cf-interleaved-thinking.md:** Removed deprecated beta header `interleaved-thinking-2025-05-14` (incompatible with Sonnet 4.6 current-gen); corrected Haiku 4.5 constraint (extended thinking NOT supported)
- **013-cf-interleaved-thinking.md:** Fixed API param examples (corrected field names for `thinking` object structure)

### Tool List Constraint (WARNING)
- **cf-router.md:** Removed BANNED tool reference (Grep — violates rule 005-cf-code-search constraint to use `rg` only)

### Rule Metadata (WARNING — enables rule 007 enforcement)
- **005-cf-code-search, 007-cf-context-loading, 008-cf-worklog, 009-cf-module-index, 011-cf-kernel-prompts, 013-cf-interleaved-thinking, 014-cf-tool-result-clearing:** Added `skip_on_bugfix: true` YAML field to all 7 domain/integration rules; makes rule 007 loading constraint enforceable at session start

### Skill Pattern Matching (MINOR)
- **extract-lessons:** Corrected content search pattern (slug uses filename, not content); pattern now matches actual ledger file format
- **record-failure:** Fixed filename slug pattern in search; now matches UUID-slug naming convention
- **compile-wiki:** Clarified search pattern for wiki entry matching

### Index Tracking (MINOR)
- **core/_index.yaml:** Added missing `installed_claude` tracking fields for 3 rule entries; aligns rule installation with index source of truth

## Rationale

Static analysis catches format issues but cannot detect:
1. Runtime OS incompatibilities (bash version features)
2. Hook environment assumptions that break in test/CI contexts
3. Stale reference data (model context windows, API params)
4. Constraint violations in prose (BANNED tool usage)
5. Missing constraint metadata (breaks rule routing logic)
6. Pattern mismatches (search pattern vs actual file naming)

The benchmark suite (ADR-004) measured token cost but not behavior. This pass established that "works as defined" requires execution-level testing of all artifacts (not just static schema validation).

## Consequences

**Positive:**
- All CRITICAL runtime failures resolved; ContextForge now passes end-to-end functional test
- Rule 007 (context loading) now enforceable at session start via `skip_on_bugfix` metadata
- Hook behavior now independent of environment variable assumptions
- Hook/script error handling now predictable across CI/local test contexts
- Reference data (model context windows, API examples) now current and accurate

**Negative/Tradeoffs:**
- None. All fixes are backwards-compatible. No breaking changes to public APIs or skill/agent contracts.

**Future Direction:**
- Integrate functional test suite into CI pipeline (`npm run test:functional`) to catch regressions early
- Add model version validation to prevent stale API params (e.g., check `claude-opus-4-7` is available before use in examples)
- Extend hook testability pattern to all remaining hooks (currently only pre-compact-anchor.sh uses fallback detection)

## References

- `core/scripts/tools/token-counter.sh` — fixed bash 3.2 compat
- `core/scripts/tools/record-failure.sh` — fixed bash 4.0+ feature
- `hooks/pre-compact-anchor.sh` — added CLAUDE_PLUGIN_ROOT fallback
- `core/rules/005-cf-code-search.yaml`, `007-cf-context-loading.yaml`, `008-cf-worklog.yaml`, `009-cf-module-index.yaml`, `011-cf-kernel-prompts.yaml`, `013-cf-interleaved-thinking.yaml`, `014-cf-tool-result-clearing.yaml` — added skip_on_bugfix metadata
- `core/rules/010-cf-context-budget.yaml` — corrected model context windows
- `core/rules/013-cf-interleaved-thinking.md` — removed deprecated beta header; corrected API examples
- `core/agents/cf-router.md` — removed BANNED tool reference
- `core/_index.yaml` — added missing installed_claude fields
