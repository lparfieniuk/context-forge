# Prompt Caching

## SYSTEM CONSTRAINTS

NEVER interleave large static files with conversational text — breaks KV prefix.
NEVER place timestamps, request UUIDs, or `<system-reminder>` tags in the system prompt.
NEVER re-attach the same bundle/context file in subsequent messages once loaded.
ALWAYS load static immutable context (rules, bundles) at the absolute beginning of the prompt.
ALWAYS treat tool results as transient data placed at the end of context.
NEVER ingest volatile data (multi-line logs, dynamic lint errors) into the system prompt.
NEVER use 5-min TTL for rules accessed less than once per 5 minutes — ALWAYS use extended 1h TTL (costs 2x writes, saves all re-reads).
NEVER exceed 4 cache breakpoints total (1 tools, 1 system, 2 messages).
ALWAYS add a second cache breakpoint if conversation exceeds 20 message blocks.
NEVER assume thinking blocks are free for caching — they invalidate KV cache in tool-heavy flows.
NEVER prune or evict context from the MIDDLE of the message array — any mutation that shifts the layout behind an existing breakpoint causes a prefix mismatch and invalidates the cache from that point on. ALWAYS clear the OLDEST CONTIGUOUS block and keep the suffix layout stable (`keep: {"type": "tool_uses", "value": N}` does exactly this). TokenPilot (arXiv:2606.17016, abstract verified 2026-08-17) names this as the failure of naive text-pruning/memory-eviction schemes; its prefix-stabilising design reports 56–61% cost reduction in isolated mode and up to 87% in continuous mode.
NEVER let tool results accumulate past 30K tokens — ALWAYS use `context_management.edits` with `clear_tool_uses_20250919` to clear re-fetchable results.
ALWAYS use documented compaction controls only; SDK compaction uses `compaction_control` / `compactionControl`.

## Static Context Placement Protocol

1. **Static Payload First:** Rules, shadow bundles, and reference docs at prompt start.
2. **Volatile Data Last:** Tool outputs, logs, and dynamic results go at end of context.
3. **No Re-attachment:** Bundle attached once → stays in KV cache. Re-attaching breaks prefix.
4. **Observation Masking:** Replace large tool outputs with `[details hidden]` after summarizing.

## Cache Cost Table

| Operation | Cost multiplier |
|---|---|
| 5-min cache write (default) | 1.25x base input |
| 1-hour cache write | 2x base input |
| Cache read (hit) | 0.1x base input |
| Break-even (5m TTL) | 1 read |
| Break-even (1h TTL) | 2 reads |

Default TTL is 5 minutes; the 1-hour TTL is opt-in (`cache_control: {type: "ephemeral", ttl: "1h"}`). Verified against docs 2026-07-21: a circulating claim that Anthropic "cut the 1-hour cache to 5 minutes in early 2026, raising costs 30–60%" is FALSE — the 1h TTL is not deprecated and both multipliers above are current. Do not weaken the extended-TTL constraint on that rumor.

Max breakpoints: 4 total (1 tools, 1 system, 2 messages). System checks up to 20 blocks backward — add second message breakpoint beyond 20 blocks.

## KV Cache Prefix Stability Rules

| Action | Effect on Cache |
|--------|----------------|
| Add content at end | Cache preserved |
| Modify beginning of prompt | Cache invalidated |
| Re-attach same bundle | Prefix broken → full re-tokenization |
| Insert timestamp in system prompt | Cache invalidated every request |
| Clear oldest contiguous tool results | Cache preserved — suffix layout unchanged |
| Prune/evict a block from the middle | Prefix mismatch → cache invalid from that point |

## Context Management API

| Primitive | API key | Cost | Use when |
|---|---|---|---|
| Tool result clearing | `clear_tool_uses_20250919` | No summarization call | Re-fetchable results >30K tokens |
| Thinking clearing | `clear_thinking_20251015` | No summarization call | Stale or excessive thinking blocks |
| Client-side SDK compaction | `compaction_control` / `compactionControl` | May summarize | SDK-managed context compaction |

Use `context_management={"edits": [...]}` for clearing edits. `clear_tool_uses_20250919`
uses `trigger`, typed `keep`, and optional `clear_at_least`; `clear_thinking_20251015`
uses `keep: {"type": "thinking_turns", "value": 2}` or `keep: "all"`.

## Few-shot example

**Input:** "I need to refactor across 10 files in the billing lib."
**Reasoning:** User needs static context. Attach bundle ONCE at start, never re-attach.
**Output:**
Open a new session. In your first message, attach the billing bundle once via `npm run bundle -- --preset=billing`. Do not re-attach it in subsequent replies.

## Validation gate (MANDATORY before context-loading instructions)

- [ ] Static context advised to load at session start (not mid-conversation)?
- [ ] No instruction to re-attach same bundle in subsequent messages?
- [ ] Volatile logs/results pushed to end of context, not beginning?
- [ ] No timestamps or dynamic values in system prompt advice?
- [ ] Extended 1h TTL used for rules accessed less than once per 5 minutes?
- [ ] Total cache breakpoints ≤4 (1 tools + 1 system + 2 messages)?
- [ ] Second message breakpoint added if conversation exceeds 20 blocks?
- [ ] Tool results monitored — `clear_tool_uses_20250919` triggered before 30K token accumulation?
- [ ] Clearing guidance uses `context_management.edits` and typed `keep` params?
If any unchecked → fix before returning instructions.
