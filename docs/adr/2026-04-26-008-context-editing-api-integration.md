# ADR-008: Anthropic Context Editing API Integration

**Date:** 2026-04-26
**Status:** Accepted
**Deciders:** lukasz-parfieniuk

## Context

Anthropic released the Context Editing API (beta `context-management-2025-06-27`) providing two new primitives: tool result clearing (zero inference cost) and server-side compaction with `instructions` parameter. These primitives enable re-fetched tool results and transient context to be removed at zero inference cost before context serialization, and allow lossy compaction that preserves semantic intent via constraint instructions. Previously, ContextForge relied solely on LLM-based Scribe summarization, which incurs full inference overhead even for results that will be re-fetched or discarded.

## Decision

1. **Update `core/rules/006-cf-prompt-caching.md`** to document Context Editing API integration: `clear_tool_uses_20250919` primitive for tool result clearing, `compact_20260112` for server-side compaction with `instructions` field to prevent domain fact loss.
2. **Create new rule `core/rules/014-cf-context-editing.md`** dedicated to context editing primitives with decision tree, examples, and activation triggers distinct from caching.
3. **Separate from caching rule** because context editing is a distinct API surface with different activation patterns ("tool result", "clear_tool_uses", "compact") and different mental model (mutation of context before serialization vs cache key optimization).

## Rationale

### API Advantages vs Summarization

**Tool Result Clearing (`clear_tool_uses_20250919`):**
- Zero inference cost: removes results from serialization without LLM processing
- Use case: bash output, rg output, API responses that will be re-fetched in next step
- Anthropic benchmark: 335K → 173K peak tokens with clearing on typical agentic flow (48% reduction)

**Server-Side Compaction (`compact_20260112` + `instructions`):**
- Runs on Anthropic's infrastructure: no inference cost to agent
- `instructions` parameter preserves semantic intent without explicit summarization
- Example: "Preserve decision rationale and error types, remove variable values and timestamps" → lossy but semantically safe
- Use case: large context blocks that are read once, then static (logs, prior responses)

**vs LLM Summarization (Scribe):**
- Scribe: full inference cost, LLM judgment required, high fidelity
- Context editing: zero cost, deterministic rules, acceptable fidelity for transient data
- Anthropic data: 7% of total spend on re-fetched tool result summarization alone; context editing eliminates this entirely

### When to Use Each

| Primitive | Data | Use Case | Cost |
|---|---|---|---|
| **clear_tool_uses** | Re-fetched results (bash, rg, curl) | Remove after reading, will fetch again | $0 |
| **compact** + `instructions` | Transient context (logs, prior LLM output) | One-time read, static for remainder | $0 |
| **Scribe** (summarize) | High-value data (code, business logic) | One read, must preserve all detail | $200–1k |

### Separate Rule Justification

Context editing and prompt caching target different problems:
- **Caching** (rule 006): Reduce repeated reads of static content (rules, shadows, reference docs)
- **Context editing** (rule 014): Remove transient content before any serialization (tool results, logs, ephemeral LLM output)

Different triggers, different mental model, different API contracts — merging would create a hybrid rule that obscures the distinct decision trees and activation conditions. Separate rule preserves clarity.

## Consequences

**Positive:**
- Eliminates 7% of session spend on re-fetched result summarization (Anthropic data)
- 48% peak token reduction on typical agentic flows (Anthropic benchmark: 335K → 173K)
- Zero inference cost for transient content — no trade-off between masking and reasoning accuracy
- `instructions` parameter allows lossy compaction without semantic loss
- Separate rule 014 provides clear activation path without caching rule complexity

**Negative/Tradeoffs:**
- Requires API support: only available on latest Claude 4 models with beta header `context-management-2025-06-27`
- Older agent code paths unable to benefit (Sonnet 4, Haiku 4.0 before beta)
- `compact` with `instructions` requires careful constraint authoring — bad instructions reduce fidelity
- Clearing tool results breaks lineage if result needs to be re-examined (must re-fetch)

## Adoption Path

1. **Phase 1 (immediate):** Document in rule 006 and 014; agents opt-in via `context-editing: enabled` in Task() params
2. **Phase 2 (month 1):** Auto-enable `clear_tool_uses` for >5KB tool results in cf-router (Tier validation agent)
3. **Phase 3 (month 2):** Teach cf-scribe to emit `compact` instructions for logs; measure cost reduction

## References

- Anthropic Context Editing API docs: `context-management-2025-06-27` beta
- Anthropic cookbook benchmark: 335K → 173K peak tokens with tool result clearing on agentic flow
- `core/rules/006-cf-prompt-caching.md` (updated with Context Editing section)
- `core/rules/014-cf-context-editing.md` (new dedicated rule)
- `core/agents/cf-router.md` (auto-enable clearing in Tier validation)
