---
name: adr-verbatim
description: Records a decision as a short ADR in the project's docs/adr/, keeping the user's own wording and dropping conversational noise. Use when the user says "zapisz to jako ADR", "nowy ADR", "zapisz decyzję", "adr-verbatim", "record this decision", "document that as an ADR". Do NOT use for a session diary entry (that is diary) or for end-of-session learnings (session-learnings); never write an ADR the user did not ask for — suggest one instead.
model: inherit
---

## What This Does

Turns a decision the user just made into a durable record future agents read before changing it.


## Steps

1. Find the folder: `docs/adr/` in the repo root (create it if absent and the user asked).
2. Number: next free `NNNN` from `ls docs/adr/ | sort | tail -1`. File: `docs/adr/NNNN-<kebab-slug>.md`.
3. Write in English (project files rule), keep the user's own phrasing for the decision itself:

```markdown
# NNNN. <Title>

- Status: accepted
- Date: YYYY-MM-DD
- Supersedes: NNNN (only if it does)

## Context
<2-4 sentences: the forces and the state of the project at the time>

## Decision
<the decision, in the user's words>

## Consequences
<what gets easier, what gets harder, what is now ruled out>
```

## Constraints

- NEVER rewrite or delete an old ADR. A reversed decision gets a NEW ADR with `Supersedes:`;
  the old one only gains `Status: superseded by NNNN`.
- ≤40 lines. No meeting notes, no alternatives survey unless the user stated them.
- Print the path when done.

Adapted from github.com/davidondrej/skills (MIT).

## Few-shot

**Input:** "zapisz to jako ADR: zostajemy przy Nx zamiast Turborepo, bo mamy już generatory"
**Output:** `docs/adr/0004-stay-on-nx.md` — Context: monorepo tooling review; Decision: "stay on Nx
instead of Turborepo because we already have generators"; Consequences: Nx upgrades stay on us.
