# ADR-003: Model ID Anchoring in Tier Routing

**Date:** 2026-04-26
**Status:** Accepted
**Deciders:** lukasz-parfieniuk

## Context

`core/rules/003-cf-tier-routing.md` and `core/rules/010-cf-context-budget.md` referenced model tiers by abstract names ("Haiku", "Sonnet", "Opus") without pinning specific model IDs. The Claude 4 lineup (Haiku 4.5, Sonnet 4.6, Opus 4.7) introduced capability differences — notably, interleaved thinking is automatic on Opus 4.7 — that make abstract tier names insufficient for deterministic routing decisions.

## Decision

Added exact model IDs to both rules (Haiku 4.5: `claude-haiku-4-5-20251001`, Sonnet 4.6: `claude-sonnet-4-6`, Opus 4.7: `claude-opus-4-7`), noted 200k context window and ~120-140k effective agentic window for all three, added an Opus 4.7 escalation gate (>10 files + novel architecture required), and introduced a 2,000-token sub-agent output contract to prevent context flooding at the coordinator level.

## Rationale

Routing decisions that rely only on abstract tier names fail silently when model capabilities differ: an agent may route to "Opus" expecting standard thinking behavior but receive automatic interleaved thinking with unbounded token cost. Pinning model IDs makes the behavior deterministic and auditable.

The 2,000-token output contract is justified by research showing a 100% actionable rate with structured multi-agent coordination vs 1.7% for single-agent approaches — constraining sub-agent verbosity is necessary to capture that gain without flooding the coordinator context window.

## Consequences

**Positive:**
- Routing decisions are deterministic and model-ID-auditable
- Opus 4.7 escalation gate prevents accidental cost spikes from over-routing
- 2,000-token output contract keeps coordinator context manageable in deep sub-agent chains
- Model ID table serves as a quick reference for API call construction

**Negative/Tradeoffs:**
- Pinned model IDs require manual update when new model versions release — abstract names were implicitly forward-compatible
- Rules grew modestly (tier routing: 86 → 93 lines, context budget: 59 → 69 lines)

## References

- Anthropic model documentation: Claude 4 lineup (2025)
- Research: multi-agent coordination actionability rate (100% structured vs 1.7% single-agent)
- `core/rules/003-cf-tier-routing.md`
- `core/rules/010-cf-context-budget.md`
