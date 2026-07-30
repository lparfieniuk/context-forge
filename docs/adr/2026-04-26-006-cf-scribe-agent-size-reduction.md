# ADR-006: cf-scribe Agent Size Reduction

**Date:** 2026-04-26
**Status:** Accepted
**Deciders:** lukasz-parfieniuk

## Context

Agent `cf-scribe.md` was 110 lines, exceeding the 100-line threshold flagged by the new `benchmark-tokens.sh` script. The agent is dispatched frequently (Scribe is a Tier 2 executor that masks large outputs before primary context reads them), so agent definition size directly impacts per-dispatch cost. Each additional line adds ~6–8 tokens when the agent is loaded into a Task() call.

## Decision

Merged redundant sections and consolidated examples:
1. **Merged Input/Output Contract:** Collapsed separate "Input Contract" and "Output Contract" subsections into a single "I/O Contract" section (single header, unified purpose)
2. **Removed redundant example:** Deleted second "Few-shot example" that duplicated the first (both illustrated Scribe dispatch for log compression)
3. **Consolidated worklog/search examples:** Merged the separate "Worklog compression" and "Search results" examples into a single combined example showing both patterns

**Result:** 110 → 92 lines (18-line reduction, ~14% shrink), line count now below threshold.

## Rationale

Every line of the cf-scribe agent definition is loaded when Scribe is dispatched via `Task(subagent_type: "scribe", ...)`. Smaller agent definition = lower token cost per dispatch.

Token impact per dispatch:
- Baseline (110 lines): ~624 tokens
- Post-edit (92 lines): ~524 tokens
- Savings: ~100 tokens per Scribe invocation

In typical development sessions, Scribe is dispatched 2–4 times (log analysis, large output masking). Session savings: 200–400 tokens.

No loss of clarity — merged sections retain all constraints and examples. I/O contract section is clearer as a single block; consolidated examples illustrate both patterns equally.

## Consequences

**Positive:**
- Reduced per-dispatch cost by ~100 tokens (~16% improvement)
- Scribe agent definition now below 100-line threshold
- Merged structure is clearer (single I/O contract vs two separate sections)
- Session-level savings: 200–400 tokens for typical multi-Scribe flows

**Negative/Tradeoffs:**
- None — no information removed, only redundancy eliminated
- Merged examples are more compact but no less illustrative

## References

- `core/agents/cf-scribe.md` (92 lines post-edit)
- `core/scripts/tools/benchmark-tokens.sh` (detects size violations)
- Benchmark baseline: `~/Projects/context-forge/core/benchmarks/baseline-2026-04-26.tsv`
