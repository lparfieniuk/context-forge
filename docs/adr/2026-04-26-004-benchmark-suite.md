# ADR-004: Benchmark Suite for Token Efficiency

**Date:** 2026-04-26
**Status:** Accepted
**Deciders:** lukasz-parfieniuk

## Context

No measurement infrastructure existed in ContextForge. Rule upgrades were applied without quantitative before/after comparison, making it impossible to detect token regressions or verify that efficiency improvements were real.

## Decision

Created `core/scripts/tools/benchmark-tokens.sh` (token counting + baseline capture via word-count proxy) and `core/scripts/tools/audit-rules.sh` (rule quality audit checking for few-shot examples, validation gates, and soft language violations), with TSV baseline captured at `core/benchmarks/`. Baseline as of 2026-04-26: 13 rules, 15 skills, 2 agents; ~7,740 estimated tokens (rules only), ~14,919 tokens (all content); 0 soft violations; all 13 rules pass quality audit.

## Rationale

Without baselines, regression is invisible. A rule that doubles in size is indistinguishable from a necessary improvement without a prior measurement to compare against. The word-count token estimation (words x 1.3) is a reliable proxy for actual tokenization within ±15%, which is sufficient for relative comparison between versions. The audit script enforces rule quality gates (few-shot, validation gate, no soft language) automatically, replacing manual review.

One agent file (`cf-scribe.md`, 110 lines) was flagged above the 100-line threshold — this is tracked as a known finding rather than a blocker.

## Consequences

**Positive:**
- Future rule changes have a quantitative before/after comparison baseline
- Audit script catches quality regressions (missing few-shot, soft language) automatically
- TSV format keeps benchmark data diff-friendly in git

**Negative/Tradeoffs:**
- Word-count token estimation is an approximation (±15%) — real token counts require an API call or tokenizer library; accepted as good-enough for relative comparison
- Benchmark scripts add maintenance surface: they must be updated if rule directory structure changes
- `cf-scribe.md` flagged at 110 lines but not yet refactored — leaves one known quality finding open

## References

- `core/scripts/tools/benchmark-tokens.sh`
- `core/scripts/tools/audit-rules.sh`
- `core/benchmarks/` (baseline TSV)
