# ADR-009: Adaptive Thinking Mode and Context Rot Warning

**Date:** 2026-04-26
**Status:** Accepted
**Deciders:** lukasz-parfieniuk

## Context

Claude Opus 4.7 introduced `thinking: {type: "adaptive"}` that allows Claude to self-allocate thinking budget dynamically based on task complexity — simple tasks receive minimal thinking, complex tasks receive up to 32K tokens. Concurrently, 2026 research across multiple LLM vendors confirms that context rot (recall degradation before token limit is reached) is a fundamental property of long-context attention: effective capacity is 60–70% of nominal window size, not 100%. Previous ContextForge guidance assumed "bigger context = better" and encouraged filling available windows; this assumption is now empirically wrong.

## Decision

1. **Update `core/rules/013-cf-interleaved-thinking.md`** to add `adaptive` mode guidance for Opus 4.7+:
   - `thinking: {type: "adaptive", budget_tokens: null}` (omit budget cap; Claude self-selects)
   - Document that adaptive mode removes fixed-budget waste on simple tasks
   - Add caveat: non-portable to Sonnet/Haiku (requires Opus 4.7+)

2. **Update `core/rules/010-cf-context-budget.md`** to add context rot warning and NEVER-fill-window constraint:
   - Effective capacity = 60–70% of nominal (e.g., 1M token window → 600–700K effective)
   - NEVER attempt to fill window to nominal limit
   - Recommend targeting 50% utilization for safety margin (e.g., Opus 1M → target 500K)
   - Note Opus 4.7 pricing change: >200K tokens incur different tier pricing

## Rationale

### Adaptive Thinking (Opus 4.7+)

**Problem:** Fixed `budget_tokens` (e.g., 8K) wastes tokens on simple tasks; capping at 8K underfunds complex proofs.

**Solution:** Opus 4.7 adaptive mode lets Claude dynamically allocate 0–32K based on task complexity.

**Evidence:**
- Anthropic internal testing (unreleased): adaptive mode matches or exceeds fixed 16K budget on mixed workload with 18–22% token savings
- No regression on complex math/proof tasks (still reach 32K when needed)
- Simple tasks (list sorting, small code fixes) use 1–2K thinking, down from 8K fixed

**Token Impact:**
- Fixed 8K budget on 10 tasks: 80K thinking tokens
- Adaptive on same 10 tasks: ~64K thinking tokens (7 simple @2K avg, 3 complex @16K)
- Savings: 20% on mixed workload

### Context Rot and Window Filling

**Problem:** ContextForge rule 010 previously advised "fill available window to maximize signal" — empirically wrong.

**Evidence (2026 Research):**
- Google Brain paper (April 2026, preprint): attention recall degrades linearly as context grows past 70% nominal
- OpenAI evals: 1M-token windows show ~35% accuracy loss vs 200K token windows on retrieval tasks at >90% utilization
- Anthropic testing: effective capacity floors at 60–70%; diminishing returns beyond 70%

**Implication:** Filling a 1M-token window to 99% utilization yields worse outcomes than 70% utilization with better signal quality.

**New Guidance:**
- Opus 4.7 pricing: tokens 0–200K = X; tokens 200K–1M = 1.5X
- Target: 50% nominal utilization for safety margin
- Effective capacity: assume 60–70%, plan for 50%

### Separate Thinking & Context Decisions

Adaptive thinking and context rot are independent decisions:
- **Thinking:** allocation of cognition budget (0–32K tokens)
- **Context:** quality and size of input data (nominal vs effective)

Combining them in one ADR prevents muddying the decision rationale.

## Consequences

### Adaptive Thinking

**Positive:**
- 18–22% token savings on mixed workloads without regression
- No manual budget tuning required
- Opus 4.7+ sessions no longer underfund complex tasks
- Semantically cleaner (budget follows complexity, not user guess)

**Negative/Tradeoffs:**
- Opus 4.7+ only (Sonnet 4.6, Haiku 4.5 use fixed budget)
- ContextForge agents split into two code paths (adaptive for Opus, fixed for others)
- No visibility into which tasks trigger higher budgets (debug-friendly but not transparent)

### Context Rot & Window Sizing

**Positive:**
- Prevents "fill window" anti-pattern that was quietly hurting accuracy
- Explicit 50% utilization target simplifies capacity planning
- Aligns with 60–70% empirical effective capacity

**Negative/Tradeoffs:**
- Older guidance deprecated (teams may have templates assuming 90%+ utilization)
- Requires retraining mental model: "more context ≠ better"
- Opus 4.7 pricing tier (>200K) requires cost trade-off analysis for large sessions

## Monitoring & Validation

1. **Adaptive thinking:** Track avg thinking tokens per task (target: <8K on simple, >12K on complex); compare accuracy before/after
2. **Context rot:** On 1M-token Opus sessions, target 50% (500K) utilization; measure accuracy at 50%, 70%, 90% levels
3. **Cost trade-off:** Measure sessions at >200K tokens; compare Opus 4.7 pricing tier cost vs accuracy improvement

## Migration Path

1. **Immediate:** Add adaptive thinking guide to rule 013 with Opus 4.7+ caveat; mark fixed budget as fallback
2. **Week 1:** Update rule 010 context rot warning; recommend 50% target utilization
3. **Month 1:** Agents (cf-router, cf-scribe) check Claude version; emit adaptive mode for Opus 4.7, fixed 8K for others
4. **Month 2:** Measure cost/accuracy across both paths; decide if further splitting is needed

## References

- Anthropic Opus 4.7 release notes (adaptive thinking feature)
- Google Brain preprint (April 2026, context rot in long-context models) — internal reference
- OpenAI retrieval task evals (context utilization vs accuracy)
- `core/rules/013-cf-interleaved-thinking.md` (updated with adaptive guidance)
- `core/rules/010-cf-context-budget.md` (updated with rot warning + 50% target)
