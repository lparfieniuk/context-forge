---
name: session-handoff
description: >
  Compresses live session state into a paste-able payload so `/clear` costs no
  context. Runs session-handoff.sh for the deterministic half (git, worklog),
  then the model fills the judgment half (locked decisions, verified vs assumed,
  next step). Use when context capacity hits WARNING/PRESSURE, before `/clear`,
  or when handing work to a fresh session.
  <example>
  Context: Capacity at 72%, refactor half-finished, user wants a clean window.
  user: "/session-handoff"
  assistant: "[HANDOFF] payload ready — 11 decisions, 3 unverified. Copy, /clear, paste."
  </example>
model: haiku
tier: 1
---

# Session Handoff

Beats `/compact`: compaction summarises the whole transcript (lossy, slow, and it
re-summarises noise). A handoff DISCARDS the transcript and rebuilds only the
state that matters — typically 5–10% of the window instead of 40%+.

## Constraints

NEVER include tool output, file contents, search dumps, or transcript quotes in the payload — those are re-fetchable and are exactly what the handoff exists to drop.
NEVER write a claim into `Verified` that you did not see a command confirm this session. Everything else goes under `Assumed` — an assumption promoted to fact is how a fresh session inherits a bug (rule 004).
ALWAYS keep the payload under 1500 tokens. Over budget → cut Assumed and Deferred first, NEVER Decisions or Next step.
ALWAYS name files as `path:line` references, NEVER paste their content.
NEVER run this as a substitute for `/end-session` — handoff carries state to the NEXT window, `/end-session` closes the work out (diary, learnings, commit).

## Steps

1. Run the deterministic half:
   ```bash
   bash core/scripts/tools/session-handoff.sh
   ```
2. Fill the judgment half from the live session (only you have it — it is not in git).
3. Emit the full payload in one fenced block so the user can copy it in one action.
4. Tell the user the sequence: copy → `/clear` → paste as first message.

## Payload template

```markdown
## Handoff — <repo> @ <branch>

### Goal
<one sentence: what this session is trying to land>

### Locked decisions
- <decision> — <why, ≤1 line>
- <decision> — <why>

### Verified (command-confirmed this session)
- <claim> — `<command that confirmed it>`

### Assumed (NOT verified — check before relying on)
- <assumption> — <what would settle it>

### Shipped
- `path/to/file.ts:42` — <what changed>

### Deferred
- <edge case / open question>

### Next step
<the single next action, concrete enough to start without asking>

<paste the session-handoff.sh output block here>
```

## Few-shot example

**Input:** `/session-handoff` at 74% capacity, mid-refactor.

**Reasoning:** PRESSURE zone (rule 010). Script gives git facts. Judgment half must separate what was actually run from what was inferred — the refactor's tests were never executed, so that goes under Assumed, not Verified.

**Output:**
```markdown
## Handoff — billing-api @ feature/tenant-scope

### Goal
Thread tenantId through AuthService and its 5 callers.

### Locked decisions
- tenantId as required param, not optional — optional silently no-ops the guard.

### Verified (command-confirmed this session)
- 12 call sites updated — `rg -c tenantId src/auth/` → 12

### Assumed (NOT verified — check before relying on)
- Suite still green — `npm test` NOT run this session. Run it first.

### Shipped
- `src/auth/auth.service.ts:88` — tenantId added to all public methods

### Next step
Run `npm test`; if red, start at auth.service.spec.ts.
```

## Validation gate (MANDATORY before emitting payload)

- [ ] No tool output, file contents, or transcript quotes in the payload?
- [ ] Every `Verified` line names the command that confirmed it?
- [ ] Everything unconfirmed placed under `Assumed` with a settling check?
- [ ] Files referenced as `path:line`, not pasted?
- [ ] Payload under 1500 tokens?
- [ ] `Next step` concrete enough to act on with zero prior context?
If any unchecked → fix before emitting.
