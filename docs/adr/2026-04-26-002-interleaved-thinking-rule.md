# ADR-002: Interleaved Thinking Rule Addition

**Date:** 2026-04-26
**Status:** Accepted
**Deciders:** lukasz-parfieniuk

## Context

Claude 4 (released May 2025) introduced interleaved thinking — reasoning blocks emitted between tool calls rather than only at the start of a response. ContextForge had no guidance on this capability, leaving `budget_tokens` uncapped and cache invalidation behavior undocumented for tool-heavy agentic flows.

## Decision

Created new rule `core/rules/013-cf-interleaved-thinking.md` + `.yaml` (63 lines, intelligent activation mode) covering: `budget_tokens` cap recommendations, cache implications of thinking blocks, and a second-breakpoint strategy for tool-heavy flows where thinking occurs mid-context.

## Rationale

Without a `budget_tokens` cap, interleaved thinking cost is unbounded — a single complex tool-use chain can silently consume tens of thousands of tokens in reasoning. Cache invalidation is a non-obvious failure mode: thinking blocks are not cacheable (per ADR-001), so inserting them between tool calls breaks the static prefix and forces re-payment of cache write costs on all subsequent reads.

The rule uses intelligent activation mode, so it only loads when thinking-related patterns appear in context — keeping the always-on token budget unaffected.

## Consequences

**Positive:**
- Prevents unbounded cost from uncapped `budget_tokens` in production agentic pipelines
- Documents the cache-invalidation interaction before it causes silent regressions
- Second-breakpoint strategy gives a concrete pattern for preserving cache hit rates in tool-heavy flows

**Negative/Tradeoffs:**
- +63 lines / ~499 tokens added to the rule set
- Rule is intelligent mode (not always-on), so authors must know to mention "thinking" to trigger it — discovery depends on keyword matching

## References

- Anthropic Claude 4 release notes (May 2025): Extended thinking and interleaved thinking
- `core/rules/013-cf-interleaved-thinking.md`
- ADR-001 (cache TTL and breakpoint limits)
