# ADR-001: Extended TTL Prompt Caching Adoption

**Date:** 2026-04-26
**Status:** Accepted
**Deciders:** lukasz-parfieniuk

## Context

Rule `006-cf-prompt-caching.md` only referenced the 5-minute cache TTL. Anthropic introduced a 1-hour extended TTL in early 2025, which is relevant for slow agentic workflows where consecutive rule reads occur more than 5 minutes apart.

## Decision

Updated `core/rules/006-cf-prompt-caching.md` (42 → 59 lines) to add: explicit 1h TTL guidance, maximum 4 cache breakpoints per prompt, 20-block context lookback limit, note that thinking blocks are not cacheable, and a cost table (cache writes 1.25x, reads 0.1x, break-even at ~2 requests).

## Rationale

For agentic sessions lasting >5 minutes — the common case for multi-step development tasks — the 5-min TTL causes cache misses on every rule re-read. The 1h TTL eliminates this at a 2x write cost premium. Break-even is reached after just 2 reads of the same cached content, making adoption unambiguously ROI-positive for any session that re-reads rules more than once.

The 4-breakpoint cap and 20-block lookback prevent over-caching volatile content (tool outputs, dynamic observations), which would invalidate the static prefix and negate caching benefits.

## Consequences

**Positive:**
- Eliminates cache misses for slow agentic workflows (>5 min between rule reads)
- Explicit break-even table gives authors a concrete decision criterion
- Thinking-block exclusion prevents a silent cost trap in Claude 4 sessions

**Negative/Tradeoffs:**
- 1h TTL incurs a 2x write cost premium on first cache population — cost-negative for sessions that read rules only once
- Rule grew by 17 lines (+40%); slightly more token load at first read

## References

- Anthropic API docs: Prompt Caching (2025 update, extended TTL)
- `core/rules/006-cf-prompt-caching.md`
