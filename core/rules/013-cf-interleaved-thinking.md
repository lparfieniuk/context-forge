# Interleaved Thinking Protocol

## SYSTEM CONSTRAINTS

SCOPE: this rule governs DIRECT Messages API calls. Claude Code's Task/Agent tool does NOT expose `thinking`/`effort` (it manages subagent effort internally, default `xhigh`) — for Task() dispatch the only lever is `model`.
`effort` is NOT a field of `thinking` — ALWAYS pass it as `output_config: {effort: …}`. Nesting it inside `thinking` returns a 400.
Adaptive thinking is OFF by default on Opus 4.7/4.8 — a request with no `thinking` field runs WITHOUT thinking. ALWAYS set `thinking: {type: "adaptive"}` explicitly to enable it.
On Opus 4.7/4.8 and Fable 5, `budget_tokens` is REMOVED — `thinking: {type: "enabled", budget_tokens: N}` returns a 400. Use `thinking: {type: "adaptive"}` + `output_config: {effort: …}`.
On Sonnet 5, adaptive thinking is ON by default (unlike Opus 4.7/4.8) — omit `thinking` to keep it on; pass `thinking: {type: "disabled"}` to turn it off. `budget_tokens` is NOT supported (400) — control depth via `output_config: {effort: …}`.
On legacy Sonnet 4.6, `budget_tokens` is DEPRECATED — PREFER `thinking: {type: "adaptive"}`. Keep `budget_tokens` only as a transitional escape hatch (must be `< max_tokens`).
On Fable 5, thinking is ALWAYS ON — omit the `thinking` param entirely. An explicit `thinking: {type: "disabled"}` returns a 400.
Haiku 4.5 does NOT support extended thinking — NEVER pass a `thinking` param to it.
The `interleaved-thinking-2025-05-14` beta header is DEPRECATED — adaptive thinking enables interleaved thinking automatically. NEVER add it for current-gen models.
NEVER assume `thinking` blocks are cacheable with `cache_control` — they are NOT.
ALWAYS add a second message-level cache breakpoint when adaptive thinking is active in tool-heavy flows (>5 tool calls).
`thinking.display` defaults to `"omitted"` on Fable 5 / Opus 4.8 / 4.7 (the `thinking` text is empty) — set `display: "summarized"` when reasoning is surfaced to a user/log.

## Thinking by Model (June 2026)

| Model | Thinking param | Depth control | Notes |
|---|---|---|---|
| `claude-haiku-4-5-20251001` | none (unsupported) | — | NEVER pass `thinking` |
| `claude-sonnet-5` | `{type: "adaptive"}` (ON by default) | `output_config.effort` | current Sonnet; `budget_tokens` 400; `xhigh` + `max` supported; `{type:"disabled"}` allowed |
| `claude-sonnet-4-6` (legacy) | `{type: "adaptive"}` (preferred) | `output_config.effort` | `budget_tokens` deprecated (transitional only); `effort` supports up to `max` |
| `claude-opus-4-6` | `{type: "adaptive"}` | `output_config.effort` | `budget_tokens` removed; `max` effort supported |
| `claude-opus-4-7` | `{type: "adaptive"}` (OFF by default) | `output_config.effort` | adds `xhigh`; `budget_tokens` 400 |
| `claude-opus-4-8` | `{type: "adaptive"}` (OFF by default) | `output_config.effort` | same surface as 4.7; current Opus |
| `claude-fable-5` | always-on (omit param) | `output_config.effort` | `{type:"disabled"}` → 400; raw CoT never returned |

`budget_tokens` (fixed thinking budget) is a deprecated/removed concept — `output_config.effort` replaces it. Do NOT introduce `budget_tokens` in new code.

## Effort Levels (`output_config: {effort: …}`)

| effort | Use case | Support |
|---|---|---|
| `"low"` | Simple/latency-sensitive tasks, subagents | all effort-capable models |
| `"medium"` | Balanced default | all |
| `"high"` | Deep reasoning, intelligence-sensitive work (recommended minimum) | all |
| `"xhigh"` | Best for coding/agentic (Claude Code default) | Opus 4.7+, Sonnet 5, Fable 5 (NOT Haiku) |
| `"max"` | Correctness over cost; hardest tasks | Opus 4.6+, Sonnet 5, Sonnet 4.6, Fable 5 (NOT Haiku) |

Default is `high` (equivalent to omitting `effort`). Lower effort → fewer/consolidated tool calls, less preamble.

## Cache Impact in Agentic Flows

Tool-heavy flow (>5 tool calls) with adaptive thinking:
- Each thinking block inserted between tool calls shifts the message array.
- `thinking` blocks are not cacheable — they break the KV cache prefix beyond the block.

Mitigation: add a second message-level breakpoint after the 5th tool result to re-anchor the cache prefix. (Also: changing the model or tool set mid-session invalidates the cache regardless.)

## Few-shot example

**Input:** Agent flow with 10 tool calls on Opus 4.8.

**Reasoning:** Opus 4.8 adaptive thinking is OFF by default → set it explicitly. Depth via `output_config.effort` (NOT inside `thinking`). >5 tool calls → add a second cache breakpoint after tool result 5.

**Output (Opus 4.8 — adaptive):**
```python
response = client.messages.create(
    model="claude-opus-4-8",
    max_tokens=64000,                      # stream for large outputs
    thinking={"type": "adaptive", "display": "summarized"},
    output_config={"effort": "xhigh"},     # effort lives here, NOT in thinking
    # Second cache breakpoint injected after 5th tool result in messages array
    messages=[...tool_results_1_to_5_with_cache_control..., ...rest...],
)
```

**Output (Sonnet 5 — adaptive ON by default; `thinking` optional):**
```python
response = client.messages.create(
    model="claude-sonnet-5",
    max_tokens=16000,
    # thinking omitted — Sonnet 5 has adaptive thinking on by default
    output_config={"effort": "medium"},
    messages=[...],
)
```

**Output (Fable 5 — thinking always-on):**
```python
response = client.messages.create(
    model="claude-fable-5",
    max_tokens=16000,
    # NO thinking param — always on; {type:"disabled"} would 400
    output_config={"effort": "high"},
    messages=[...],
)
```

## Validation gate (MANDATORY before enabling thinking)

- [ ] `effort` passed via `output_config`, NOT nested in `thinking`?
- [ ] For Opus 4.7/4.8: `thinking: {type: "adaptive"}` set explicitly (OFF by default)?
- [ ] No `budget_tokens` on Opus 4.6/4.7/4.8 or Fable 5 (returns 400)?
- [ ] For Fable 5: `thinking` param omitted entirely (no `{type:"disabled"}`)?
- [ ] NEVER passing a `thinking` param to Haiku 4.5 (unsupported)?
- [ ] If >5 tool calls: second message-level cache breakpoint added?
- [ ] Beta header `interleaved-thinking-2025-05-14` NOT used (deprecated)?
- [ ] If reasoning is shown to a user: `display: "summarized"` set (default is `"omitted"`)?
If any unchecked → fix before enabling thinking.
