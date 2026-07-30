# Context Budget

## SYSTEM CONSTRAINTS

ALWAYS treat effective context capacity as 60–70% of advertised window, NOT 100%.
NEVER spawn a Tier 3 agent without checking current capacity estimate first.
At 70% capacity: ALWAYS force Scribe dispatch for all subsequent tool outputs.
At 80% capacity: BLOCK all new Tier 3 agent spawns. Recommend session restart.
NEVER ignore capacity warnings. Each threshold has a mandatory action.
NEVER rely on large context window to avoid context management — context rot is real regardless of window size.
Context rot begins BEFORE hitting token limit — n² attention means recall degrades progressively.

## Current Model Context Windows

| Model ID | Context | Effective (agentic) |
|---|---|---|
| `claude-haiku-4-5-20251001` | 200k | ~120–140k |
| `claude-sonnet-5` | 1M | ~600–700k (context rot warning — do NOT rely on full window) |
| `claude-opus-4-8` | 1M (standard pricing across the full window — no long-context premium) | ~600–700k (context rot warning — do NOT rely on full window) |

Interleaved thinking adds overhead per tool call turn — each thinking block consumes additional tokens beyond the response. Account for this in capacity estimates when interleaved thinking is active.

## Capacity Estimation Formula

```
estimated_usage   = system_prompt_tokens + rule_tokens + conversation_tokens + tool_output_tokens
effective_limit   = model_limit * 0.65   # midpoint of 60–70% effective range
capacity_pct      = estimated_usage / effective_limit * 100
```

Context quality degrades before the hard limit. 83.9% of tokens in agentic systems come from tool outputs — ALWAYS track these via Scribe dispatch.

## Threshold Actions

| Capacity % | Status | Mandatory Action |
|-----------|--------|-----------------|
| <60% | Normal | No restriction |
| 60–69% | WARNING | Emit warning in session status |
| 70–79% | PRESSURE | Force Scribe dispatch for all tool outputs; warn before Tier 3 spawn |
| ≥80% | CRITICAL | BLOCK new Tier 3 spawns; recommend session restart |

## Session Status Block

SessionStart hook emits:
```
CONTEXT BUDGET STATUS:
  model_limit: <N> tokens
  effective_limit: <N*0.65> tokens
  estimated_usage: ~<N> tokens
  capacity_pct: ~<N>%
  status: NORMAL | WARNING | PRESSURE | CRITICAL
```

## Few-shot example

**Input:** Session has consumed ~68% of effective capacity. User asks to spawn 2 Tier 3 agents.
**Reasoning:** 68% = WARNING zone. Spawning Tier 3 will push toward PRESSURE. Warn before proceeding.
**Output:**
```
CONTEXT BUDGET WARNING: ~68% capacity used.
Spawning 2 Tier 3 agents will consume additional ~2–10k tokens each.
Recommend: complete current task, start fresh session for next sub-task.
Proceed? [y/n]
```

## Validation gate (MANDATORY before Tier 3 spawn or large tool output)

- [ ] Current capacity % estimated before Tier 3 spawn?
- [ ] If ≥70%: Scribe dispatched for tool outputs (not raw output in context)?
- [ ] If ≥80%: Tier 3 spawn BLOCKED and session restart recommended?
If any unchecked → apply threshold action before proceeding.
