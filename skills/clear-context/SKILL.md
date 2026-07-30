---
name: clear-context
description: >
  Orchestrates tool result and thinking block clearing. Checks accumulated context
  pressure (threshold: 30K tokens) and emits correct context_management.edits params.
  Implements rule 014-cf-tool-result-clearing workflow.
  <example>
  Context: Agentic session, tool results at 45K tokens
  user: "/clear-context"
  assistant: "[CLEAR-CONTEXT] Action: clear_tool_uses_20250919 via context_management.edits; keeping 3 tool uses."
  </example>
model: none
---

## What This Does

Implements the decision tree from rule 014 (`cf-tool-result-clearing`) as an executable
workflow. Measures accumulated tool result and thinking block size, picks the cheapest
documented primitive, and emits the required `context_management` params.

**Decision tree:**
```
Tool results > 30K AND results are re-fetchable?
  YES → use clear_tool_uses_20250919
  NO  → thinking blocks stale or too large?
        YES → use clear_thinking_20251015
        NO  → consider documented compaction guidance outside this skill
```

## When to Use

**Trigger:** Tool results accumulating past 30K tokens; stale or excessive thinking blocks;
conversation approaching 50% context window; before spawning expensive Tier 3 subagent;
proactively every 20+ tool calls.

**Never needed:** When context is fresh (<10K tool result tokens).

## How to Use

### Step 1 — Measure tool result accumulation

Estimate by counting recent tool result blocks. Rough formula:
- Each file read ≈ (file lines × 5) tokens
- Each rg result ≈ (match count × 20) tokens
- Each bash output ≈ (output lines × 8) tokens

If estimate > 30K: proceed to clearing.

### Step 2 — Determine if results are re-fetchable

Re-fetchable (safe to clear): file reads, search results, directory listings, git status.
NOT re-fetchable (do NOT clear): agent responses containing decisions, architectural choices,
error root causes, any content not reproducible by re-running the tool.

### Step 3 — Emit context_management params

**For tool result clearing (re-fetchable results > 30K tokens):**
```python
# In the next API call, include:
context_management={
    "edits": [{
        "type": "clear_tool_uses_20250919",
        "trigger": {"type": "input_tokens", "value": 30000},
        "keep": {"type": "tool_uses", "value": 3},
        "clear_at_least": {"type": "input_tokens", "value": 5000},
    }]
}
```

**For thinking block clearing:**
```python
context_management={
    "edits": [{
        "type": "clear_thinking_20251015",
        "trigger": {"type": "input_tokens", "value": 30000},
        "keep": {"type": "thinking_turns", "value": 2},
    }]
}
```

Compaction is separate from clearing. Client-side SDK compaction uses `compaction_control`
or `compactionControl`; compaction may use summarization depending on the API or SDK.

## Output Format

```
[CLEAR-CONTEXT]
- Tool result estimate: 45K tokens (threshold: 30K)
- Re-fetchable: YES (file reads + search results)
- API: context_management.edits
- Action: clear_tool_uses_20250919
- Keep: {"type": "tool_uses", "value": 3}
- Effect: reduces serialized context by clearing older re-fetchable tool uses
[END CLEAR-CONTEXT]
```

## Constraints

NEVER clear tool results that contain decisions, root causes, or non-reproducible content.
NEVER use summarization when documented clearing is sufficient for re-fetchable content.
ALWAYS emit `context_management.edits` with the action type selected.
ALWAYS emit `[CLEAR-CONTEXT]` prefix so the coordinator can track the action.
NEVER invoke compaction guidance when tool result or thinking clearing is sufficient.
